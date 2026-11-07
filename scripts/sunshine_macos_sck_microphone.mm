/**
 * @file src/platform/macos/microphone.mm
 * @brief macOS system audio capture via ScreenCaptureKit (SCStream) with fallback to AVAudio.
 *
 * Uses Apple's ScreenCaptureKit audio capture (authorized under Screen Recording permission,
 * which is pre-granted natively on Namespace macOS Sequoia environments) to capture crisp
 * 48kHz stereo desktop & game audio without requiring separate Microphone / CATap TCC prompts.
 */
#include "src/config.h"
#include "src/logging.h"
#include "src/platform/common.h"
#include "src/platform/macos/av_audio.h"

#import <CoreMedia/CoreMedia.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <time.h>
#include <vector>

@interface SCKAudioCapture : NSObject <SCStreamOutput, SCStreamDelegate> {
@public
  TPCircularBuffer audioSampleBuffer;
  dispatch_semaphore_t audioSemaphore;
@private
  SCStream *_stream;
  dispatch_queue_t _audioQueue;
  dispatch_source_t _silenceTimer;
  std::atomic<uint64_t> _lastAudioNs;
  uint32_t _sampleRate;
  uint32_t _channels;
  bool _bufferInitialized;
  std::atomic<bool> _stopped;
  std::atomic<bool> _loggedFirstPacket;
}

- (int)startWithSampleRate:(uint32_t)sampleRate channels:(uint32_t)channels displayID:(CGDirectDisplayID)preferredDisplayID;
- (void)stopCaptureSession;
@end

@implementation SCKAudioCapture

- (instancetype)init {
  self = [super init];
  if (self) {
    _stream = nil;
    _audioQueue = nil;
    _silenceTimer = nil;
    _lastAudioNs.store(0);
    _sampleRate = 48000;
    _channels = 2;
    _bufferInitialized = false;
    _stopped.store(false);
    _loggedFirstPacket.store(false);
    audioSemaphore = nil;
  }
  return self;
}

- (int)startWithSampleRate:(uint32_t)sampleRate channels:(uint32_t)channels displayID:(CGDirectDisplayID)preferredDisplayID {
  _sampleRate = sampleRate > 0 ? sampleRate : 48000;
  _channels = channels > 0 ? channels : 2;

  uint32_t ringBytes = _sampleRate * _channels * sizeof(float) * 2;  // 2 seconds buffer
  if (!TPCircularBufferInit(&audioSampleBuffer, ringBytes)) {
    return -1;
  }
  _bufferInitialized = true;
  audioSemaphore = dispatch_semaphore_create(0);
  _audioQueue = dispatch_queue_create("com.lizardbyte.sunshine.sck.audio", DISPATCH_QUEUE_SERIAL);
  _lastAudioNs.store(clock_gettime_nsec_np(CLOCK_UPTIME_RAW));

  __block SCDisplay *chosenDisplay = nil;
  __block NSError *contentErr = nil;
  dispatch_semaphore_t contentSem = dispatch_semaphore_create(0);

  [SCShareableContent getShareableContentExcludingDesktopWindows:NO
                                             onScreenWindowsOnly:NO
                                               completionHandler:^(SCShareableContent *content, NSError *error) {
                                                 if (error || !content || content.displays.count == 0) {
                                                   contentErr = [error retain];
                                                 } else {
                                                   for (SCDisplay *d in content.displays) {
                                                     if (preferredDisplayID != 0 && d.displayID == preferredDisplayID) {
                                                       chosenDisplay = [d retain];
                                                       break;
                                                     }
                                                   }
                                                   if (!chosenDisplay) {
                                                     chosenDisplay = [content.displays.firstObject retain];
                                                   }
                                                 }
                                                 dispatch_semaphore_signal(contentSem);
                                               }];

  if (dispatch_semaphore_wait(contentSem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC)) != 0 || !chosenDisplay) {
    if (contentErr) {
      [contentErr release];
    }
    dispatch_release(contentSem);
    return -1;
  }
  dispatch_release(contentSem);

  SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:chosenDisplay excludingWindows:@[]];
  [chosenDisplay release];

  SCStreamConfiguration *cfg = [[SCStreamConfiguration alloc] init];
  cfg.width = 64;
  cfg.height = 64;
  cfg.capturesAudio = YES;
  cfg.sampleRate = (NSInteger)_sampleRate;
  cfg.channelCount = (NSInteger)_channels;
  cfg.excludesCurrentProcessAudio = YES;

  _stream = [[SCStream alloc] initWithFilter:filter configuration:cfg delegate:self];
  [filter release];
  [cfg release];

  NSError *addErr = nil;
  if (![_stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:_audioQueue error:&addErr]) {
    return -1;
  }
  [_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:_audioQueue error:nil];

  __block bool startOk = false;
  dispatch_semaphore_t startSem = dispatch_semaphore_create(0);
  [_stream startCaptureWithCompletionHandler:^(NSError *error) {
    startOk = (error == nil);
    dispatch_semaphore_signal(startSem);
  }];

  bool waitedOk = (dispatch_semaphore_wait(startSem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC)) == 0);
  dispatch_release(startSem);
  if (!waitedOk || !startOk) {
    return -1;
  }

  // Silence fallback timer: keeps Opus clocked smoothly if SCStream pauses packets during total silence
  _silenceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _audioQueue);
  dispatch_source_set_timer(_silenceTimer, dispatch_time(DISPATCH_TIME_NOW, 20LL * NSEC_PER_MSEC), 10LL * NSEC_PER_MSEC, 2LL * NSEC_PER_MSEC);
  SCKAudioCapture *weakSelf = self;
  dispatch_source_set_event_handler(_silenceTimer, ^{
    if (weakSelf->_stopped.load()) {
      return;
    }
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    uint64_t last = weakSelf->_lastAudioNs.load();
    if (now > last && (now - last) > 35000000ULL) {
      uint32_t avail = 0;
      TPCircularBufferTail(&weakSelf->audioSampleBuffer, &avail);
      uint32_t lowWaterBytes = (weakSelf->_sampleRate / 25) * weakSelf->_channels * sizeof(float);
      if (avail < lowWaterBytes) {
        uint32_t silenceFrames = weakSelf->_sampleRate / 100;  // 10ms
        std::vector<float> zeros(silenceFrames * weakSelf->_channels, 0.0f);
        TPCircularBufferProduceBytes(&weakSelf->audioSampleBuffer, zeros.data(), static_cast<uint32_t>(zeros.size() * sizeof(float)));
        dispatch_semaphore_signal(weakSelf->audioSemaphore);
      }
    }
  });
  dispatch_resume(_silenceTimer);

  return 0;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
  if (type != SCStreamOutputTypeAudio || _stopped.load()) {
    return;
  }
  if (!CMSampleBufferDataIsReady(sampleBuffer)) {
    return;
  }
  CMItemCount numFrames = CMSampleBufferGetNumSamples(sampleBuffer);
  if (numFrames <= 0) {
    return;
  }

  CMAudioFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
  const AudioStreamBasicDescription *asbd = fmt ? CMAudioFormatDescriptionGetStreamBasicDescription(fmt) : nullptr;
  bool isFloat = !asbd || ((asbd->mFormatFlags & kAudioFormatFlagIsFloat) != 0);
  bool isNonInterleaved = asbd && ((asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);

  alignas(16) uint8_t ablStorage[sizeof(AudioBufferList) + sizeof(AudioBuffer) * 8];
  std::memset(ablStorage, 0, sizeof(ablStorage));
  auto *abl = reinterpret_cast<AudioBufferList *>(ablStorage);
  CMBlockBufferRef blockBuffer = nullptr;

  size_t neededBytes = 0;
  OSStatus stSize = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
    sampleBuffer, &neededBytes, nullptr, 0, nullptr, nullptr, 0, nullptr
  );
  OSStatus st = -1;
  if (stSize == noErr && neededBytes > 0 && neededBytes <= sizeof(ablStorage)) {
    st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      nullptr,
      abl,
      neededBytes,
      nullptr,
      nullptr,
      0,
      &blockBuffer
    );
  }

  std::vector<float> out(static_cast<size_t>(numFrames) * _channels, 0.0f);

  if (st == noErr && abl->mNumberBuffers > 0 && abl->mBuffers[0].mData) {
    if (isFloat && isNonInterleaved) {
      const auto *ch0 = reinterpret_cast<const float *>(abl->mBuffers[0].mData);
      const auto *ch1 = (abl->mNumberBuffers > 1 && abl->mBuffers[1].mData)
                          ? reinterpret_cast<const float *>(abl->mBuffers[1].mData)
                          : ch0;
      if (_channels == 2) {
        for (CMItemCount i = 0; i < numFrames; ++i) {
          out[2 * i] = ch0[i];
          out[2 * i + 1] = ch1[i];
        }
      } else {
        for (CMItemCount i = 0; i < numFrames; ++i) {
          for (uint32_t c = 0; c < _channels; ++c) {
            const auto *src = (c < abl->mNumberBuffers && abl->mBuffers[c].mData)
                                ? reinterpret_cast<const float *>(abl->mBuffers[c].mData)
                                : ch0;
            out[i * _channels + c] = src[i];
          }
        }
      }
    } else if (isFloat && !isNonInterleaved) {
      const auto *src = reinterpret_cast<const float *>(abl->mBuffers[0].mData);
      uint32_t srcCh = (asbd && asbd->mChannelsPerFrame > 0) ? asbd->mChannelsPerFrame : _channels;
      for (CMItemCount i = 0; i < numFrames; ++i) {
        for (uint32_t c = 0; c < _channels; ++c) {
          out[i * _channels + c] = src[i * srcCh + (c < srcCh ? c : 0)];
        }
      }
    }
    if (blockBuffer) {
      CFRelease(blockBuffer);
    }
  } else {
    if (blockBuffer) {
      CFRelease(blockBuffer);
    }
    // Fallback: read directly from CMBlockBuffer
    CMBlockBufferRef dataBuf = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!dataBuf) {
      return;
    }
    size_t totalBytes = CMBlockBufferGetDataLength(dataBuf);
    size_t planeBytes = static_cast<size_t>(numFrames) * sizeof(float);
    if (totalBytes < planeBytes) {
      return;
    }
    std::vector<float> raw(totalBytes / sizeof(float));
    if (CMBlockBufferCopyDataBytes(dataBuf, 0, raw.size() * sizeof(float), raw.data()) != kCMBlockBufferNoErr) {
      return;
    }
    const float *ch0 = raw.data();
    const float *ch1 = (totalBytes >= planeBytes * 2) ? (raw.data() + numFrames) : ch0;
    for (CMItemCount i = 0; i < numFrames; ++i) {
      if (_channels == 2) {
        out[2 * i] = ch0[i];
        out[2 * i + 1] = ch1[i];
      } else {
        out[i] = ch0[i];
      }
    }
  }

  if (TPCircularBufferProduceBytes(&audioSampleBuffer, out.data(), static_cast<uint32_t>(out.size() * sizeof(float)))) {
    _lastAudioNs.store(clock_gettime_nsec_np(CLOCK_UPTIME_RAW));
    dispatch_semaphore_signal(audioSemaphore);
    bool exp = false;
    if (_loggedFirstPacket.compare_exchange_strong(exp, true)) {
      BOOST_LOG(info) << "ScreenCaptureKit first audio packet delivered (" << numFrames << " frames, st=" << st << ")";
    }
  }
}

- (void)stopCaptureSession {
  bool expected = false;
  if (!_stopped.compare_exchange_strong(expected, true)) {
    return;
  }
  if (_silenceTimer) {
    dispatch_source_cancel(_silenceTimer);
    dispatch_release(_silenceTimer);
    _silenceTimer = nil;
  }
  if (_stream) {
    dispatch_semaphore_t stopSem = dispatch_semaphore_create(0);
    [_stream stopCaptureWithCompletionHandler:^(NSError *error) {
      dispatch_semaphore_signal(stopSem);
    }];
    dispatch_semaphore_wait(stopSem, dispatch_time(DISPATCH_TIME_NOW, 2LL * NSEC_PER_SEC));
    dispatch_release(stopSem);
    [_stream release];
    _stream = nil;
  }
  if (audioSemaphore) {
    dispatch_semaphore_signal(audioSemaphore);
  }
}

- (void)dealloc {
  [self stopCaptureSession];
  if (_audioQueue) {
    dispatch_release(_audioQueue);
    _audioQueue = nil;
  }
  if (audioSemaphore) {
    dispatch_release(audioSemaphore);
    audioSemaphore = nil;
  }
  if (_bufferInitialized) {
    TPCircularBufferCleanup(&audioSampleBuffer);
    _bufferInitialized = false;
  }
  [super dealloc];
}

@end

namespace platf {
  using namespace std::literals;

  struct sck_mic_t: public mic_t {
    SCKAudioCapture *sck_capture {};

    ~sck_mic_t() override {
      if (sck_capture) {
        [sck_capture stopCaptureSession];
        [sck_capture release];
        sck_capture = nil;
      }
    }

    capture_e sample(std::vector<float> &sample_in) override {
      const uint32_t neededBytes = static_cast<uint32_t>(sample_in.size() * sizeof(float));
      auto *dst = reinterpret_cast<uint8_t *>(sample_in.data());
      uint32_t remaining = neededBytes;

      while (remaining > 0) {
        uint32_t avail = 0;
        void *tail = TPCircularBufferTail(&sck_capture->audioSampleBuffer, &avail);

        if (avail == 0) {
          dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC);
          if (dispatch_semaphore_wait(sck_capture->audioSemaphore, timeout) != 0) {
            BOOST_LOG(warning) << "SCK audio sample timeout"sv;
            std::fill(sample_in.begin(), sample_in.end(), 0.0f);
            return capture_e::timeout;
          }
          continue;
        }

        const uint32_t toCopy = (avail < remaining) ? avail : remaining;
        std::memcpy(dst, tail, toCopy);
        TPCircularBufferConsume(&sck_capture->audioSampleBuffer, toCopy);
        dst += toCopy;
        remaining -= toCopy;
      }
      return capture_e::ok;
    }
  };

  struct av_mic_t: public mic_t {
    AVAudio *av_audio_capture {};

    ~av_mic_t() override {
      [av_audio_capture release];
    }

    capture_e sample(std::vector<float> &sample_in) override {
      const uint32_t neededBytes = static_cast<uint32_t>(sample_in.size() * sizeof(float));
      auto *dst = reinterpret_cast<uint8_t *>(sample_in.data());
      uint32_t remaining = neededBytes;

      while (remaining > 0) {
        uint32_t avail = 0;
        void *tail = TPCircularBufferTail(&av_audio_capture->audioSampleBuffer, &avail);

        if (avail == 0) {
          dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC);
          if (dispatch_semaphore_wait(av_audio_capture->audioSemaphore, timeout) != 0) {
            BOOST_LOG(warning) << "Audio sample timeout - no audio data received within 5 seconds"sv;
            std::fill(sample_in.begin(), sample_in.end(), 0.0f);
            return capture_e::timeout;
          }
          continue;
        }

        const uint32_t toCopy = (avail < remaining) ? avail : remaining;
        std::memcpy(dst, tail, toCopy);
        TPCircularBufferConsume(&av_audio_capture->audioSampleBuffer, toCopy);
        dst += toCopy;
        remaining -= toCopy;
      }
      return capture_e::ok;
    }
  };

  struct macos_audio_control_t: public audio_control_t {
    AVCaptureDevice *audio_capture_device {};

  public:
    int set_sink(const std::string &sink) override {
      return 0;
    }

    std::unique_ptr<mic_t> microphone(const std::uint8_t *mapping, int channels, std::uint32_t sample_rate, std::uint32_t frame_size, bool continuous_audio, bool host_audio_enabled) override {
      if (config::audio.sink.empty()) {
        CGDirectDisplayID prefDisp = 0;
        if (!config::video.output_name.empty()) {
          prefDisp = static_cast<CGDirectDisplayID>(std::strtoul(config::video.output_name.c_str(), nullptr, 10));
        }

        auto sck_mic = std::make_unique<sck_mic_t>();
        sck_mic->sck_capture = [[SCKAudioCapture alloc] init];

        BOOST_LOG(info) << "Using macOS ScreenCaptureKit audio capture (48kHz native)."sv;
        BOOST_LOG(info) << "Sample rate: "sv << sample_rate << ", Frame size: "sv << frame_size << ", Channels: "sv << channels;

        if ([sck_mic->sck_capture startWithSampleRate:sample_rate channels:static_cast<uint32_t>(channels) displayID:prefDisp] == 0) {
          BOOST_LOG(info) << "ScreenCaptureKit audio capture started successfully!"sv;
          return sck_mic;
        }

        BOOST_LOG(warning) << "ScreenCaptureKit audio failed, falling back to CoreAudio system tap."sv;
      }

      auto mic = std::make_unique<av_mic_t>();
      mic->av_audio_capture = [[AVAudio alloc] init];
      mic->av_audio_capture.hostAudioEnabled = host_audio_enabled ? YES : NO;

      if (config::audio.sink.empty()) {
        if ([mic->av_audio_capture setupSystemTap:sample_rate frameSize:frame_size channels:channels]) {
          BOOST_LOG(error) << "Failed to setup system audio tap."sv;
          return nullptr;
        }
      } else {
        const char *audio_sink = config::audio.sink.c_str();
        if (!request_microphone_permission()) {
          return nullptr;
        }
        if ((audio_capture_device = [AVAudio findMicrophone:[NSString stringWithUTF8String:audio_sink]]) == nullptr) {
          return nullptr;
        }
        if ([mic->av_audio_capture setupMicrophone:audio_capture_device sampleRate:sample_rate frameSize:frame_size channels:channels]) {
          return nullptr;
        }
      }

      return mic;
    }

    bool is_sink_available(const std::string &sink) override {
      return true;
    }

    std::optional<sink_t> sink_info() override {
      sink_t sink;
      return sink;
    }
  };

  std::unique_ptr<audio_control_t> audio_control() {
    return std::make_unique<macos_audio_control_t>();
  }
}  // namespace platf
