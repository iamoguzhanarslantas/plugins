// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// HealthKit workout session for watchOS. See the header for the contract.
//
// Every change to the session runs on one serial queue, so the HealthKit and
// CoreLocation callbacks, which arrive on threads of their own, never race the
// calls Dart makes. What Dart reads back (state, metrics, buffered locations,
// request results, queued errors) is a snapshot under `_lock`, written from
// that queue and copied out by the FFI reads.

#import "flutter_watch_workout_ffi.h"

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <HealthKit/HealthKit.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

// Where `start` records whether the session records a route, so `recover`
// can pick the route back up after the app was relaunched.
static NSString* const kRouteDefaultsKey =
    @"dev.flutterwatch.flutter_watch_workout.route";

// Route points worse than this, in metres, are left out of the route, as in
// Apple's workout sample.
static const CLLocationAccuracy kRouteAccuracy = 50;

// How many session errors wait for Dart before the oldest is dropped.
static const NSUInteger kErrorBuffer = 32;

// ---- Snapshot read by Dart --------------------------------------------------

static os_unfair_lock _lock = OS_UNFAIR_LOCK_INIT;
static fww_signal_callback _callback = NULL;
static int _state = 0;
static NSDictionary* _metrics = nil;
static NSMutableArray<NSDictionary*>* _locations = nil;
static int64_t _droppedLocations = 0;
static NSMutableDictionary<NSNumber*, NSDictionary*>* _results = nil;
static NSMutableArray<NSDictionary*>* _errors = nil;
static int64_t _nextRequest = 1;

static void _signal(int64_t kind) {
    os_unfair_lock_lock(&_lock);
    fww_signal_callback callback = _callback;
    os_unfair_lock_unlock(&_lock);
    // Outside the lock: Dart reads the snapshot straight back.
    if (callback != NULL) {
        callback(kind);
    }
}

static dispatch_queue_t _queue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("dev.flutterwatch.flutter_watch_workout",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static char* _json(id object) {
    if (object == nil) {
        return NULL;
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:0
                                                     error:nil];
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

static NSDictionary* _error(NSString* code, NSString* message,
                            NSInteger nativeCode) {
    return @{
        @"code" : code,
        @"message" : message ?: @"",
        @"nativeCode" : @(nativeCode),
    };
}

static NSDictionary* _nsError(NSString* code, NSError* error) {
    if (error == nil) {
        return _error(code, @"The request failed without an error.", 0);
    }
    return _error(code, error.localizedDescription, error.code);
}

static int64_t _newRequest(void) {
    os_unfair_lock_lock(&_lock);
    int64_t id = _nextRequest++;
    os_unfair_lock_unlock(&_lock);
    return id;
}

// Stores the result of request `id` for Dart. Request 0 is a session end that
// no `end` call asked for, which nobody waits on.
static void _finish(int64_t id, NSDictionary* result) {
    if (id == 0) {
        return;
    }
    os_unfair_lock_lock(&_lock);
    if (_results == nil) {
        _results = [NSMutableDictionary dictionary];
    }
    _results[@(id)] = result;
    os_unfair_lock_unlock(&_lock);
    _signal(FWW_SIGNAL_REQUEST);
}

static void _fail(int64_t id, NSDictionary* error) {
    _finish(id, @{@"error" : error});
}

static void _pushError(NSDictionary* error) {
    os_unfair_lock_lock(&_lock);
    if (_errors == nil) {
        _errors = [NSMutableArray array];
    }
    [_errors addObject:error];
    if (_errors.count > kErrorBuffer) {
        [_errors removeObjectAtIndex:0];
    }
    os_unfair_lock_unlock(&_lock);
    _signal(FWW_SIGNAL_ERROR);
}

static void _setState(int state) {
    os_unfair_lock_lock(&_lock);
    _state = state;
    os_unfair_lock_unlock(&_lock);
    _signal(FWW_SIGNAL_STATE);
}

// ---- HealthKit types --------------------------------------------------------

static HKQuantityType* _quantity(HKQuantityTypeIdentifier identifier) {
    return [HKQuantityType quantityTypeForIdentifier:identifier];
}

static NSSet<HKSampleType*>* _shareTypes(void) {
    return [NSSet setWithObjects:[HKObjectType workoutType],
                                 [HKSeriesType workoutRouteType],
                                 _quantity(HKQuantityTypeIdentifierActiveEnergyBurned),
                                 _quantity(HKQuantityTypeIdentifierDistanceWalkingRunning),
                                 _quantity(HKQuantityTypeIdentifierDistanceCycling),
                                 nil];
}

static NSSet<HKObjectType*>* _readTypes(void) {
    return [NSSet setWithObjects:[HKObjectType workoutType],
                                 _quantity(HKQuantityTypeIdentifierHeartRate),
                                 _quantity(HKQuantityTypeIdentifierActiveEnergyBurned),
                                 _quantity(HKQuantityTypeIdentifierDistanceWalkingRunning),
                                 _quantity(HKQuantityTypeIdentifierDistanceCycling),
                                 nil];
}

static NSString* _sharing(HKAuthorizationStatus status) {
    switch (status) {
        case HKAuthorizationStatusSharingAuthorized:
            return @"authorized";
        case HKAuthorizationStatusSharingDenied:
            return @"denied";
        default:
            return @"notDetermined";
    }
}

static NSString* _location(CLAuthorizationStatus status) {
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways:
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            return @"authorized";
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            return @"denied";
        default:
            return @"notDetermined";
    }
}

// The usage descriptions HealthKit (and CoreLocation, for a route) terminate
// an app without. Checked before either framework is asked for anything.
static NSArray<NSString*>* _missingKeys(BOOL route) {
    NSMutableArray<NSString*>* missing = [NSMutableArray array];
    NSMutableArray<NSString*>* keys = [@[
        @"NSHealthShareUsageDescription", @"NSHealthUpdateUsageDescription"
    ] mutableCopy];
    if (route) {
        [keys addObject:@"NSLocationWhenInUseUsageDescription"];
    }
    for (NSString* key in keys) {
        if ([[NSBundle mainBundle] objectForInfoDictionaryKey:key] == nil) {
            [missing addObject:key];
        }
    }
    return missing;
}

static NSDictionary* _missingKeysError(NSArray<NSString*>* missing) {
    return _error(@"missingUsageDescription",
                  [NSString stringWithFormat:@"The watch app's Info.plist has no %@.",
                                             [missing componentsJoinedByString:@", "]],
                  0);
}

// ---- The session ------------------------------------------------------------

@interface FWWWorkout : NSObject <HKWorkoutSessionDelegate,
                                  HKLiveWorkoutBuilderDelegate,
                                  CLLocationManagerDelegate>
@property(nonatomic, strong) HKHealthStore* store;
@property(nonatomic, strong) HKWorkoutSession* session;
@property(nonatomic, strong) HKLiveWorkoutBuilder* builder;
@property(nonatomic, strong) HKWorkoutRouteBuilder* routeBuilder;
@property(nonatomic, assign) NSInteger routePoints;
// The `end` or `discard` request waiting for the workout to finish, or 0.
@property(nonatomic, assign) int64_t pendingEnd;
@property(nonatomic, assign) BOOL discarding;
// Main thread only.
@property(nonatomic, strong) CLLocationManager* locationManager;
@property(nonatomic, strong) NSMutableArray<void (^)(NSString*)>* locationWaiters;
@end

static FWWWorkout* _workout(void) {
    static FWWWorkout* workout;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        workout = [[FWWWorkout alloc] init];
        workout.store = [[HKHealthStore alloc] init];
        workout.locationWaiters = [NSMutableArray array];
    });
    return workout;
}

@implementation FWWWorkout

// Main thread only: CoreLocation delivers to the run loop it was created on.
- (CLLocationManager*)manager {
    if (self.locationManager == nil) {
        CLLocationManager* manager = [[CLLocationManager alloc] init];
        manager.delegate = self;
        manager.desiredAccuracy = kCLLocationAccuracyBest;
        manager.activityType = CLActivityTypeFitness;
        manager.distanceFilter = kCLDistanceFilterNone;
        self.locationManager = manager;
    }
    return self.locationManager;
}

// Calls `done` on the session queue with the location authorization, asking
// the wearer first when nothing has been decided yet.
- (void)requestLocationThen:(void (^)(NSString*))done {
    dispatch_async(dispatch_get_main_queue(), ^{
        CLLocationManager* manager = [self manager];
        CLAuthorizationStatus status = manager.authorizationStatus;
        if (status != kCLAuthorizationStatusNotDetermined) {
            dispatch_async(_queue(), ^{
                done(_location(status));
            });
            return;
        }
        [self.locationWaiters addObject:[done copy]];
        [manager requestWhenInUseAuthorization];
    });
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        return;
    }
    NSArray<void (^)(NSString*)>* waiters = [self.locationWaiters copy];
    [self.locationWaiters removeAllObjects];
    for (void (^done)(NSString*) in waiters) {
        dispatch_async(_queue(), ^{
            done(_location(status));
        });
    }
}

- (void)startLocationUpdates {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self manager] startUpdatingLocation];
    });
}

- (void)stopLocationUpdates {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.locationManager stopUpdatingLocation];
    });
}

- (void)locationManager:(CLLocationManager*)manager
     didUpdateLocations:(NSArray<CLLocation*>*)locations {
    NSMutableArray<CLLocation*>* usable = [NSMutableArray array];
    for (CLLocation* location in locations) {
        if (location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= kRouteAccuracy &&
            fabs(location.timestamp.timeIntervalSinceNow) < 10) {
            [usable addObject:location];
        }
    }
    if (usable.count == 0) {
        return;
    }
    dispatch_async(_queue(), ^{
        [self addRouteLocations:usable];
    });
}

- (void)locationManager:(CLLocationManager*)manager
       didFailWithError:(NSError*)error {
    // kCLErrorLocationUnknown is transient: CoreLocation keeps trying.
    if (error.code == kCLErrorLocationUnknown) {
        return;
    }
    _pushError(_nsError(@"location", error));
}

// Session queue.
- (void)addRouteLocations:(NSArray<CLLocation*>*)locations {
    if (self.routeBuilder == nil ||
        self.session.state != HKWorkoutSessionStateRunning) {
        return;
    }
    [self.routeBuilder insertRouteData:locations
                            completion:^(BOOL success, NSError* error) {
        if (!success) {
            _pushError(_nsError(@"route", error));
        }
    }];
    self.routePoints += locations.count;

    NSMutableArray<NSDictionary*>* points = [NSMutableArray array];
    for (CLLocation* location in locations) {
        [points addObject:@{
            @"latitude" : @(location.coordinate.latitude),
            @"longitude" : @(location.coordinate.longitude),
            @"altitude" : @(location.altitude),
            @"horizontalAccuracy" : @(location.horizontalAccuracy),
            @"verticalAccuracy" : @(location.verticalAccuracy),
            @"speed" : @(location.speed),
            @"course" : @(location.course),
            @"timestamp" : @((int64_t)(location.timestamp.timeIntervalSince1970 * 1000)),
        }];
    }
    os_unfair_lock_lock(&_lock);
    if (_locations == nil) {
        _locations = [NSMutableArray array];
    }
    [_locations addObjectsFromArray:points];
    if (_locations.count > FWW_LOCATION_BUFFER) {
        NSUInteger overflow = _locations.count - FWW_LOCATION_BUFFER;
        [_locations removeObjectsInRange:NSMakeRange(0, overflow)];
        _droppedLocations += overflow;
    }
    os_unfair_lock_unlock(&_lock);
    _signal(FWW_SIGNAL_LOCATIONS);
}

// Session queue. The distance a workout of this activity accumulates.
- (HKQuantityType*)distanceType {
    HKWorkoutActivityType activity =
        self.session.workoutConfiguration.activityType;
    return activity == HKWorkoutActivityTypeCycling
               ? _quantity(HKQuantityTypeIdentifierDistanceCycling)
               : _quantity(HKQuantityTypeIdentifierDistanceWalkingRunning);
}

- (double)sumOf:(HKQuantityType*)type unit:(HKUnit*)unit {
    HKQuantity* sum = [self.builder statisticsForType:type].sumQuantity;
    return sum == nil ? 0 : [sum doubleValueForUnit:unit];
}

// Session queue.
- (void)publishMetrics {
    HKLiveWorkoutBuilder* builder = self.builder;
    if (builder == nil) {
        return;
    }
    HKUnit* bpm = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
    HKQuantity* heartRate =
        [builder statisticsForType:_quantity(HKQuantityTypeIdentifierHeartRate)]
            .mostRecentQuantity;
    NSDictionary* metrics = @{
        @"heartRate" : heartRate == nil ? [NSNull null]
                                        : @([heartRate doubleValueForUnit:bpm]),
        @"activeEnergy" : @([self sumOf:_quantity(HKQuantityTypeIdentifierActiveEnergyBurned)
                                   unit:[HKUnit kilocalorieUnit]]),
        @"distance" : @([self sumOf:[self distanceType] unit:[HKUnit meterUnit]]),
        @"elapsed" : @(builder.elapsedTime),
        @"timestamp" : @((int64_t)([NSDate date].timeIntervalSince1970 * 1000)),
    };
    os_unfair_lock_lock(&_lock);
    _metrics = metrics;
    os_unfair_lock_unlock(&_lock);
    _signal(FWW_SIGNAL_METRICS);
}

// Session queue.
- (void)attachSession:(HKWorkoutSession*)session route:(BOOL)route {
    self.session = session;
    self.builder = [session associatedWorkoutBuilder];
    if (self.builder.dataSource == nil) {
        self.builder.dataSource = [[HKLiveWorkoutDataSource alloc]
               initWithHealthStore:self.store
              workoutConfiguration:session.workoutConfiguration];
    }
    session.delegate = self;
    self.builder.delegate = self;
    self.routePoints = 0;
    self.routeBuilder =
        route ? [[HKWorkoutRouteBuilder alloc] initWithHealthStore:self.store
                                                            device:nil]
              : nil;
}

// Session queue. Forgets the finished session; the last state and metrics
// stay readable until the next one starts.
- (void)clear {
    [self stopLocationUpdates];
    self.session = nil;
    self.builder = nil;
    self.routeBuilder = nil;
    self.routePoints = 0;
    self.pendingEnd = 0;
    self.discarding = NO;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRouteDefaultsKey];
}

// Session queue.
- (void)startWithConfig:(NSDictionary*)config request:(int64_t)request {
    if (self.session != nil) {
        _fail(request, _error(@"alreadyRunning",
                              @"A workout session is already running.", 0));
        return;
    }
    if (![HKHealthStore isHealthDataAvailable]) {
        _fail(request, _error(@"notAvailable",
                              @"HealthKit is not available on this device.", 0));
        return;
    }
    BOOL route = [config[@"route"] boolValue];
    NSArray<NSString*>* missing = _missingKeys(route);
    if (missing.count > 0) {
        _fail(request, _missingKeysError(missing));
        return;
    }
    HKWorkoutConfiguration* configuration = [[HKWorkoutConfiguration alloc] init];
    configuration.activityType =
        (HKWorkoutActivityType)[config[@"activity"] unsignedIntegerValue];
    configuration.locationType =
        (HKWorkoutSessionLocationType)[config[@"location"] integerValue];
    NSError* error = nil;
    HKWorkoutSession* session =
        [[HKWorkoutSession alloc] initWithHealthStore:self.store
                                        configuration:configuration
                                                error:&error];
    if (session == nil) {
        _fail(request, _nsError(@"healthKit", error));
        return;
    }
    [self attachSession:session route:route];
    [[NSUserDefaults standardUserDefaults] setBool:route forKey:kRouteDefaultsKey];
    os_unfair_lock_lock(&_lock);
    _metrics = nil;
    [_locations removeAllObjects];
    os_unfair_lock_unlock(&_lock);

    NSDate* start = [NSDate date];
    [session startActivityWithDate:start];
    HKLiveWorkoutBuilder* builder = self.builder;
    [builder beginCollectionWithStartDate:start
                               completion:^(BOOL success, NSError* collectError) {
        dispatch_async(_queue(), ^{
            if (!success) {
                [session end];
                [builder discardWorkout];
                [self clear];
                _fail(request, _nsError(@"healthKit", collectError));
                return;
            }
            if (route) {
                [self startLocationUpdates];
            }
            [self publishMetrics];
            _finish(request, @{});
        });
    }];
}

// Session queue.
- (void)endWithRequest:(int64_t)request discard:(BOOL)discard {
    if (self.session == nil) {
        _fail(request, _error(@"noSession", @"No workout session is running.", 0));
        return;
    }
    if (self.pendingEnd != 0) {
        _fail(request, _error(@"alreadyEnding", @"The workout is already ending.", 0));
        return;
    }
    self.pendingEnd = request;
    self.discarding = discard;
    [self stopLocationUpdates];
    if (self.session.state == HKWorkoutSessionStateEnded) {
        // Ended already, by the system: finishing may be under way, and it
        // answers this request when it is done.
        [self finishAt:[NSDate date]];
    } else {
        // The rest happens when the session reports Ended.
        [self.session end];
    }
}

// Session queue. Ends collection and saves (or discards) the workout once
// the session has ended, whoever ended it.
- (void)finishAt:(NSDate*)date {
    HKLiveWorkoutBuilder* builder = self.builder;
    if (builder == nil) {
        return;
    }
    BOOL discard = self.discarding;
    // Taken now, so a second Ended report finds nothing left to finish.
    self.builder = nil;
    // Answers whichever `end` or `discard` is waiting by then, if any: the
    // session may have been ended by the system, and the call may come later.
    void (^answer)(NSDictionary*) = ^(NSDictionary* result) {
        int64_t request = self.pendingEnd;
        [self clear];
        _finish(request, result);
    };
    [builder endCollectionWithEndDate:date
                           completion:^(BOOL success, NSError* error) {
        dispatch_async(_queue(), ^{
            if (!success) {
                answer(@{@"error" : _nsError(@"healthKit", error)});
                return;
            }
            if (discard) {
                [builder discardWorkout];
                [self.routeBuilder discard];
                answer(@{});
                return;
            }
            HKUnit* kcal = [HKUnit kilocalorieUnit];
            HKQuantity* energySum =
                [builder statisticsForType:_quantity(HKQuantityTypeIdentifierActiveEnergyBurned)]
                    .sumQuantity;
            HKQuantity* distanceSum = [builder statisticsForType:[self distanceType]].sumQuantity;
            double energy = energySum == nil ? 0 : [energySum doubleValueForUnit:kcal];
            double distance =
                distanceSum == nil ? 0 : [distanceSum doubleValueForUnit:[HKUnit meterUnit]];
            [builder finishWorkoutWithCompletion:^(HKWorkout* workout, NSError* finishError) {
                dispatch_async(_queue(), ^{
                    if (workout == nil) {
                        answer(@{@"error" : _nsError(@"healthKit", finishError)});
                        return;
                    }
                    HKWorkoutRouteBuilder* routeBuilder = self.routeBuilder;
                    NSInteger points = self.routePoints;
                    void (^done)(BOOL) = ^(BOOL routeSaved) {
                        answer(@{
                            @"uuid" : workout.UUID.UUIDString,
                            @"duration" : @(workout.duration),
                            @"activeEnergy" : @(energy),
                            @"distance" : @(distance),
                            @"routePoints" : @(points),
                            @"routeSaved" : @(routeSaved),
                        });
                    };
                    if (routeBuilder == nil || points == 0) {
                        [routeBuilder discard];
                        done(NO);
                        return;
                    }
                    [routeBuilder finishRouteWithWorkout:workout
                                                metadata:nil
                                              completion:^(HKWorkoutRoute* saved,
                                                           NSError* routeError) {
                        dispatch_async(_queue(), ^{
                            if (saved == nil) {
                                _pushError(_nsError(@"route", routeError));
                            }
                            done(saved != nil);
                        });
                    }];
                });
            }];
        });
    }];
}

// ---- HKWorkoutSessionDelegate -----------------------------------------------

- (void)workoutSession:(HKWorkoutSession*)workoutSession
      didChangeToState:(HKWorkoutSessionState)toState
             fromState:(HKWorkoutSessionState)fromState
                  date:(NSDate*)date {
    dispatch_async(_queue(), ^{
        if (workoutSession != self.session) {
            return;
        }
        _setState((int)toState);
        if (toState == HKWorkoutSessionStateEnded) {
            [self stopLocationUpdates];
            [self finishAt:date];
        }
    });
}

- (void)workoutSession:(HKWorkoutSession*)workoutSession
      didFailWithError:(NSError*)error {
    _pushError(_nsError(@"session", error));
}

// ---- HKLiveWorkoutBuilderDelegate -------------------------------------------

- (void)workoutBuilder:(HKLiveWorkoutBuilder*)workoutBuilder
    didCollectDataOfTypes:(NSSet<HKSampleType*>*)collectedTypes {
    dispatch_async(_queue(), ^{
        if (workoutBuilder == self.builder) {
            [self publishMetrics];
        }
    });
}

- (void)workoutBuilderDidCollectEvent:(HKLiveWorkoutBuilder*)workoutBuilder {
    // Pause and resume events change the elapsed time.
    dispatch_async(_queue(), ^{
        if (workoutBuilder == self.builder) {
            [self publishMetrics];
        }
    });
}

@end

// ---- FFI --------------------------------------------------------------------

void flutter_watch_workout_set_callback(fww_signal_callback callback) {
    os_unfair_lock_lock(&_lock);
    _callback = callback;
    os_unfair_lock_unlock(&_lock);
}

int flutter_watch_workout_is_available(void) {
    return [HKHealthStore isHealthDataAvailable] ? 1 : 0;
}

char* flutter_watch_workout_setup_report(void) {
    id modes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"WKBackgroundModes"];
    BOOL workoutProcessing = [modes isKindOfClass:[NSArray class]] &&
                             [modes containsObject:@"workout-processing"];
    return _json(@{
        @"missing" : _missingKeys(YES),
        @"workoutProcessing" : @(workoutProcessing),
    });
}

int64_t flutter_watch_workout_request_authorization(int route) {
    int64_t request = _newRequest();
    NSArray<NSString*>* missing = _missingKeys(route != 0);
    if (missing.count > 0) {
        _fail(request, _missingKeysError(missing));
        return request;
    }
    if (![HKHealthStore isHealthDataAvailable]) {
        _fail(request, _error(@"notAvailable",
                              @"HealthKit is not available on this device.", 0));
        return request;
    }
    FWWWorkout* workout = _workout();
    [workout.store requestAuthorizationToShareTypes:_shareTypes()
                                          readTypes:_readTypes()
                                         completion:^(BOOL success, NSError* error) {
        dispatch_async(_queue(), ^{
            if (!success) {
                _fail(request, _nsError(@"healthKit", error));
                return;
            }
            NSString* sharing =
                _sharing([workout.store authorizationStatusForType:[HKObjectType workoutType]]);
            if (route == 0) {
                _finish(request, @{@"workoutSharing" : sharing, @"location" : @"notRequested"});
                return;
            }
            [workout requestLocationThen:^(NSString* location) {
                _finish(request, @{@"workoutSharing" : sharing, @"location" : location});
            }];
        });
    }];
    return request;
}

int64_t flutter_watch_workout_start(const char* config_json) {
    int64_t request = _newRequest();
    // Parsed now: Dart releases the string as soon as this returns.
    NSData* data = config_json == NULL
                       ? nil
                       : [NSData dataWithBytes:config_json length:strlen(config_json)];
    id config = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data
                                                                    options:0
                                                                      error:nil];
    if (![config isKindOfClass:[NSDictionary class]]) {
        _fail(request, _error(@"invalidConfiguration",
                              @"The workout configuration is not a JSON object.", 0));
        return request;
    }
    dispatch_async(_queue(), ^{
        [_workout() startWithConfig:config request:request];
    });
    return request;
}

void flutter_watch_workout_pause(void) {
    dispatch_async(_queue(), ^{
        [_workout().session pause];
    });
}

void flutter_watch_workout_resume(void) {
    dispatch_async(_queue(), ^{
        [_workout().session resume];
    });
}

int64_t flutter_watch_workout_end(void) {
    int64_t request = _newRequest();
    dispatch_async(_queue(), ^{
        [_workout() endWithRequest:request discard:NO];
    });
    return request;
}

int64_t flutter_watch_workout_discard(void) {
    int64_t request = _newRequest();
    dispatch_async(_queue(), ^{
        [_workout() endWithRequest:request discard:YES];
    });
    return request;
}

int64_t flutter_watch_workout_recover(void) {
    int64_t request = _newRequest();
    FWWWorkout* workout = _workout();
    [workout.store recoverActiveWorkoutSessionWithCompletion:^(HKWorkoutSession* session,
                                                               NSError* error) {
        dispatch_async(_queue(), ^{
            if (workout.session != nil) {
                _finish(request, @{@"recovered" : @YES});
                return;
            }
            if (session == nil) {
                // Nothing was running: not a failure of the call.
                _finish(request, @{@"recovered" : @NO});
                return;
            }
            BOOL route = [[NSUserDefaults standardUserDefaults] boolForKey:kRouteDefaultsKey];
            [workout attachSession:session route:route];
            _setState((int)session.state);
            if (route && session.state == HKWorkoutSessionStateRunning) {
                [workout startLocationUpdates];
            }
            [workout publishMetrics];
            _finish(request, @{@"recovered" : @YES});
        });
    }];
    return request;
}

int flutter_watch_workout_state(void) {
    os_unfair_lock_lock(&_lock);
    int state = _state;
    os_unfair_lock_unlock(&_lock);
    return state;
}

char* flutter_watch_workout_metrics(void) {
    os_unfair_lock_lock(&_lock);
    NSDictionary* metrics = _metrics;
    os_unfair_lock_unlock(&_lock);
    return _json(metrics);
}

char* flutter_watch_workout_poll_locations(void) {
    os_unfair_lock_lock(&_lock);
    NSArray<NSDictionary*>* drained = _locations.count == 0 ? nil : [_locations copy];
    [_locations removeAllObjects];
    os_unfair_lock_unlock(&_lock);
    return _json(drained);
}

int64_t flutter_watch_workout_dropped_location_count(void) {
    os_unfair_lock_lock(&_lock);
    int64_t dropped = _droppedLocations;
    os_unfair_lock_unlock(&_lock);
    return dropped;
}

char* flutter_watch_workout_take_request_result(int64_t id) {
    os_unfair_lock_lock(&_lock);
    NSDictionary* result = _results[@(id)];
    [_results removeObjectForKey:@(id)];
    os_unfair_lock_unlock(&_lock);
    return _json(result);
}

char* flutter_watch_workout_take_last_error(void) {
    os_unfair_lock_lock(&_lock);
    NSDictionary* error = _errors.firstObject;
    if (error != nil) {
        [_errors removeObjectAtIndex:0];
    }
    os_unfair_lock_unlock(&_lock);
    return _json(error);
}

void flutter_watch_workout_release(char* string) {
    free(string);
}
