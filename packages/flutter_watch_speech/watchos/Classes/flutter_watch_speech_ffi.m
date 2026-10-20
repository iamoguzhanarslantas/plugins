// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// One AVSpeechSynthesizer for the app. See the header for the contract.
//
// With "duckOthers", the audio session is set to playback in the voice-prompt
// mode, ducking other audio, while utterances are queued, and deactivated
// (letting the other audio back up) once the last one is done.

#import "flutter_watch_speech_ffi.h"

#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static fws_signal_callback _callback = NULL;
static NSMutableArray<NSDictionary*>* _events = nil;
static int64_t _nextId = 1;

static char* _json(id object) {
    if (object == nil) {
        return NULL;
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (data == nil) {
        return NULL;
    }
    char* out = malloc(data.length + 1);
    if (out == NULL) {
        return NULL;
    }
    memcpy(out, data.bytes, data.length);
    out[data.length] = '\0';
    return out;
}

static NSString* _string(const char* s) {
    return s == NULL ? nil : [NSString stringWithUTF8String:s];
}

@interface FWSSpeaker : NSObject <AVSpeechSynthesizerDelegate>
@property(nonatomic, strong) AVSpeechSynthesizer* synthesizer;
// Utterance (by address) to its id. Main thread only.
@property(nonatomic, strong) NSMutableDictionary<NSValue*, NSNumber*>* ids;
@property(nonatomic, assign) BOOL ducking;
@end

@implementation FWSSpeaker

- (void)push:(AVSpeechUtterance*)utterance type:(NSString*)type end:(BOOL)end {
    NSValue* key = [NSValue valueWithNonretainedObject:utterance];
    NSNumber* identifier = self.ids[key];
    if (identifier == nil) {
        return;
    }
    if (end) {
        [self.ids removeObjectForKey:key];
    }
    os_unfair_lock_lock(&_lock);
    if (_events == nil) {
        _events = [NSMutableArray array];
    }
    [_events addObject:@{@"id" : identifier, @"type" : type}];
    if (_events.count > FWS_EVENT_BUFFER) {
        [_events removeObjectAtIndex:0];
    }
    fws_signal_callback callback = _callback;
    os_unfair_lock_unlock(&_lock);
    if (callback != NULL) {
        callback(FWS_SIGNAL_EVENTS);
    }
    if (end && self.ids.count == 0 && self.ducking) {
        self.ducking = NO;
        [[AVAudioSession sharedInstance]
              setActive:NO
            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                  error:nil];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
    didStartSpeechUtterance:(AVSpeechUtterance*)utterance {
    [self push:utterance type:@"started" end:NO];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
    didFinishSpeechUtterance:(AVSpeechUtterance*)utterance {
    [self push:utterance type:@"finished" end:YES];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
    didCancelSpeechUtterance:(AVSpeechUtterance*)utterance {
    [self push:utterance type:@"cancelled" end:YES];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
    didPauseSpeechUtterance:(AVSpeechUtterance*)utterance {
    [self push:utterance type:@"paused" end:NO];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
    didContinueSpeechUtterance:(AVSpeechUtterance*)utterance {
    [self push:utterance type:@"continued" end:NO];
}

@end

// Created on the main thread, where its delegate callbacks then arrive.
static FWSSpeaker* _speaker(void) {
    static FWSSpeaker* speaker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^make)(void) = ^{
            speaker = [[FWSSpeaker alloc] init];
            speaker.synthesizer = [[AVSpeechSynthesizer alloc] init];
            speaker.synthesizer.delegate = speaker;
            speaker.ids = [NSMutableDictionary dictionary];
        };
        if ([NSThread isMainThread]) {
            make();
        } else {
            dispatch_sync(dispatch_get_main_queue(), make);
        }
    });
    return speaker;
}

static void _onMain(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

void flutter_watch_speech_set_callback(fws_signal_callback callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

int64_t flutter_watch_speech_speak(const char* text, const char* options_json) {
    NSString* string = _string(text) ?: @"";
    NSDictionary* options = nil;
    if (options_json != NULL) {
        NSData* data = [NSData dataWithBytes:options_json length:strlen(options_json)];
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        options = [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
    }
    os_unfair_lock_lock(&_lock);
    int64_t identifier = _nextId++;
    os_unfair_lock_unlock(&_lock);

    AVSpeechUtterance* utterance = [AVSpeechUtterance speechUtteranceWithString:string];
    id voice = options[@"voice"];
    id language = options[@"language"];
    if ([voice isKindOfClass:[NSString class]]) {
        utterance.voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voice];
    }
    if (utterance.voice == nil && [language isKindOfClass:[NSString class]]) {
        utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
    }
    id rate = options[@"rate"];
    if ([rate isKindOfClass:[NSNumber class]]) {
        // 0..1 across the synthesizer's whole range.
        float r = MAX(0.0f, MIN(1.0f, [rate floatValue]));
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate +
                         r * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate);
    }
    id pitch = options[@"pitch"];
    if ([pitch isKindOfClass:[NSNumber class]]) {
        utterance.pitchMultiplier = MAX(0.5f, MIN(2.0f, [pitch floatValue]));
    }
    id volume = options[@"volume"];
    if ([volume isKindOfClass:[NSNumber class]]) {
        utterance.volume = MAX(0.0f, MIN(1.0f, [volume floatValue]));
    }
    id pre = options[@"preDelay"];
    if ([pre isKindOfClass:[NSNumber class]]) {
        utterance.preUtteranceDelay = MAX(0.0, [pre doubleValue]);
    }
    id post = options[@"postDelay"];
    if ([post isKindOfClass:[NSNumber class]]) {
        utterance.postUtteranceDelay = MAX(0.0, [post doubleValue]);
    }
    BOOL duck = [options[@"duckOthers"] boolValue];

    FWSSpeaker* speaker = _speaker();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (duck && !speaker.ducking) {
            AVAudioSession* session = [AVAudioSession sharedInstance];
            [session setCategory:AVAudioSessionCategoryPlayback
                            mode:AVAudioSessionModeVoicePrompt
                         options:AVAudioSessionCategoryOptionDuckOthers
                           error:nil];
            speaker.ducking = [session setActive:YES error:nil];
        }
        speaker.ids[[NSValue valueWithNonretainedObject:utterance]] = @(identifier);
        [speaker.synthesizer speakUtterance:utterance];
    });
    return identifier;
}

int flutter_watch_speech_stop(void) {
    __block BOOL stopped = NO;
    FWSSpeaker* speaker = _speaker();
    _onMain(^{
        stopped = [speaker.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    });
    return stopped ? 1 : 0;
}

int flutter_watch_speech_pause(void) {
    __block BOOL paused = NO;
    FWSSpeaker* speaker = _speaker();
    _onMain(^{
        paused = [speaker.synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryWord];
    });
    return paused ? 1 : 0;
}

int flutter_watch_speech_resume(void) {
    __block BOOL resumed = NO;
    FWSSpeaker* speaker = _speaker();
    _onMain(^{
        resumed = [speaker.synthesizer continueSpeaking];
    });
    return resumed ? 1 : 0;
}

int flutter_watch_speech_is_speaking(void) {
    __block BOOL speaking = NO;
    FWSSpeaker* speaker = _speaker();
    _onMain(^{
        speaking = speaker.synthesizer.speaking;
    });
    return speaking ? 1 : 0;
}

int flutter_watch_speech_is_paused(void) {
    __block BOOL paused = NO;
    FWSSpeaker* speaker = _speaker();
    _onMain(^{
        paused = speaker.synthesizer.paused;
    });
    return paused ? 1 : 0;
}

char* flutter_watch_speech_voices(void) {
    NSMutableArray<NSDictionary*>* voices = [NSMutableArray array];
    for (AVSpeechSynthesisVoice* voice in [AVSpeechSynthesisVoice speechVoices]) {
        NSString* quality = @"default";
        if (voice.quality == AVSpeechSynthesisVoiceQualityEnhanced) {
            quality = @"enhanced";
        } else if (@available(watchOS 9.0, *)) {
            if (voice.quality == AVSpeechSynthesisVoiceQualityPremium) {
                quality = @"premium";
            }
        }
        [voices addObject:@{
            @"identifier" : voice.identifier ?: @"",
            @"name" : voice.name ?: @"",
            @"language" : voice.language ?: @"",
            @"quality" : quality,
        }];
    }
    return _json(voices);
}

char* flutter_watch_speech_current_language(void) {
    NSString* code = [AVSpeechSynthesisVoice currentLanguageCode] ?: @"";
    char* out = malloc(strlen(code.UTF8String) + 1);
    if (out != NULL) {
        strcpy(out, code.UTF8String);
    }
    return out;
}

char* flutter_watch_speech_poll_events(void) {
    os_unfair_lock_lock(&_lock);
    NSArray<NSDictionary*>* drained = _events.count == 0 ? nil : [_events copy];
    [_events removeAllObjects];
    os_unfair_lock_unlock(&_lock);
    return _json(drained);
}

void flutter_watch_speech_release(char* string) {
    free(string);
}
