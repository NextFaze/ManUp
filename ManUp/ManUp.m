//
//  ManUp.m
//  ManUpDemo
//
//  Created by Jeremy Day on 23/10/12.
//  Copyright (c) 2012 Burleigh Labs. All rights reserved.
//

#import "ManUp.h"

@interface ManUp ()

@property (nonatomic, strong) UIAlertController *alertController;

@property (nonatomic, assign) BOOL optionalUpdateShown;
@property (nonatomic, assign) BOOL updateInProgress;
@property (nonatomic, strong) NSURL *serverConfigURL;

@end

@implementation ManUp

- (void)manUpWithDefaultDictionary:(NSDictionary *)defaultSettingsDict serverConfigURL:(NSURL *)serverConfigURL delegate:(NSObject<ManUpDelegate> *)delegate {
    self.delegate = delegate;
    self.serverConfigURL = serverConfigURL;
    
    // Only apply defaults if they do not exist already.
    if(![self hasPersistedSettings]) {
        NSDictionary* nonNullDefaultSettings = [self replaceNullsWithEmptyStringInDictionary:defaultSettingsDict];
        [self setManUpSettings:nonNullDefaultSettings];
    }
    
    [self updateFromServer];
}

- (void)manUpWithDefaultJSONFile:(NSString *)defaultSettingsPath serverConfigURL:(NSURL *)serverConfigURL delegate:(NSObject<ManUpDelegate> *)delegate {
    self.delegate = delegate;
    self.serverConfigURL = serverConfigURL;
    
    // Only apply defaults if they do not exist already.
    if (![self hasPersistedSettings]) {
        NSData *jsonData = [NSData dataWithContentsOfFile:defaultSettingsPath];
        if (jsonData == nil) {
            // TODO: handle this error
            return;
        }

        NSError *error = nil;
        NSDictionary *defaultSettings = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        NSDictionary *nonNullDefaultSettings = [self replaceNullsWithEmptyStringInDictionary:defaultSettings];
        [self setManUpSettings:nonNullDefaultSettings];
    }
    
    [self updateFromServer];
}

#pragma mark - Creation

+ (ManUp *)sharedInstance {
    static id sharedInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[[self class] alloc] init];
    });

    return sharedInstance;
}

- (id)init {
	if (self = [super init]) {
		self.updateInProgress = NO;
        self.optionalUpdateShown = NO;
	}
	return self;
}

#pragma mark - 

- (NSDictionary *)replaceNullsWithEmptyStringInDictionary:(NSDictionary *)dict {
    NSMutableDictionary *newDict = [[NSMutableDictionary alloc] init];
    for (NSString *key in dict) {
        NSString *value = [dict objectForKey:key];
        if (value == nil || [value isKindOfClass:[NSNull class]]) {
            value = @"";
        }
        [newDict setValue:value forKey:key];
    }
    return newDict;
}

- (void)setManUpSettings:(NSDictionary *)settings {
    [[NSUserDefaults standardUserDefaults] setObject:settings forKey:kManUpSettings];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([self.delegate respondsToSelector:@selector(manUpConfigUpdated:)]) {
        [self.delegate manUpConfigUpdated:settings];
    }
}

- (void)setManUpSettingsIfNone:(NSDictionary*)settings {
    NSDictionary *persistedSettings = [self getPersistedSettings];
    if (persistedSettings == nil) {
        [self setManUpSettings:settings];
    }
}

- (void)setLastUpdated:(NSDate *)date {
    [[NSUserDefaults standardUserDefaults] setObject:date forKey:kManUpLastUpdated];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDate *)lastUpdated {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kManUpLastUpdated];
}

- (NSDictionary *)getPersistedSettings {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kManUpSettings];
}

- (BOOL)hasPersistedSettings {
    return [self getPersistedSettings] != nil;
}

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    if (self.enableConsoleLogging) {
        NSLog([NSString stringWithFormat:format]);
    }
}

#pragma mark -

- (void)updateFromServer {
    if (!self.serverConfigURL) {
        [self log:@"ERROR: No server config URL specified."];
        if ([self.delegate respondsToSelector:@selector(manUpConfigUpdateFailed:)]) {
            NSError *error = [NSError errorWithDomain:@"com.nextfaze.ManUp" code:1 userInfo:nil];
            [self.delegate manUpConfigUpdateFailed:error];
        }
        return;
    }
    
    if (self.updateInProgress) {
        [self log:@"ManUp: An update is currently in progress."];
        return;
    }
    
    self.updateInProgress = YES;
    if ([self.delegate respondsToSelector:@selector(manUpConfigUpdateStarting)]) {
        [self.delegate manUpConfigUpdateStarting];
    }
    
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:self.serverConfigURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                self.updateInProgress = NO;
                                                
                                                if (error) {
                                                    if ([self.delegate respondsToSelector:@selector(manUpConfigUpdateFailed:)]) {
                                                        [self.delegate manUpConfigUpdateFailed:error];
                                                    }
                                                    [self checkAppVersion];
                                                    return;
                                                }
                                                
                                                NSError *parsingError;
                                                id jsonObject = [NSJSONSerialization JSONObjectWithData:data
                                                                                                options:kNilOptions
                                                                                                  error:&parsingError];
                                                
                                                if (parsingError) {
                                                    [self log:@"ERROR: %@", parsingError];
                                                    [self log:@"\%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
                                                    if ([self.delegate respondsToSelector:@selector(manUpConfigUpdateFailed:)]) {
                                                        [self.delegate manUpConfigUpdateFailed:error];
                                                    }
                                                    [self checkAppVersion];
                                                    return;
                                                }
                                                
                                                NSDictionary *nonNullSettings = [self replaceNullsWithEmptyStringInDictionary:jsonObject];
                                                [self setManUpSettings:nonNullSettings];
                                                [self checkAppVersion];
                                                return;
                                            }];
    [task resume];
}

#pragma mark -

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message actions:(NSArray *)actions {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        
        for (UIAlertAction *action in actions) {
            [self.alertController addAction:action];
        }
        
        UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topController.presentedViewController) {
            topController = topController.presentedViewController;
        }
        [topController presentViewController:self.alertController animated:YES completion:nil];
    });
}

- (void)checkAppVersion {
    NSDictionary *settings = [self getPersistedSettings];
    NSString *updateURL  = [settings objectForKey:kManUpAppUpdateURL];
    NSString *currentVersion = [settings objectForKey:kManUpAppVersionCurrent];
    NSString *minVersion = [settings objectForKey:kManUpAppVersionMin];
    NSString *installedVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    if (![currentVersion isKindOfClass:[NSString class]]) {
        [self log:@"ManUp: Error, expecting string for key %@", kManUpAppVersionCurrent];
        return;
    }
    
    if (![minVersion isKindOfClass:[NSString class]]) {
        [self log:@"ManUp: Error, expecting string for key %@", kManUpAppVersionMin];
        return;
    }
    
    [self log:@"Current version  : %@", currentVersion];
    [self log:@"Min version      : %@", minVersion];
    [self log:@"Installed version: %@", installedVersion];
    
    NSComparisonResult minVersionComparisonResult = [ManUp compareVersion:installedVersion toVersion:minVersion];
    NSComparisonResult currentVersionComparisonResult = [ManUp compareVersion:installedVersion toVersion:currentVersion];
    
    if (!self.alertController) {
        if (minVersion && minVersionComparisonResult == NSOrderedAscending) {
            [self log:@"ManUp: Mandatory update required."];
            
            if (updateURL.length > 0) {
                [self log:@"ManUp: Blocking access and displaying update alert."];
                
                UIAlertAction *updateAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Update", nil)
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction * _Nonnull action) {
                                                                         [self openUpdateURL];
                                                                     }];
                
                [self showAlertWithTitle:NSLocalizedString(@"Update Required", nil)
                                 message:NSLocalizedString(@"An update is required. To continue, please update the application.", nil)
                                 actions:@[updateAction]];
            }
            
        } else if (currentVersion && currentVersionComparisonResult == NSOrderedAscending && !self.optionalUpdateShown) {
            [self log:@"ManUp: User doesn't have latest version."];
            
            if (updateURL.length > 0) {
                UIAlertAction *updateAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Update", nil)
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^(UIAlertAction * _Nonnull action) {
                                                                         [self openUpdateURL];
                                                                     }];
                
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No Thanks", nil)
                                                                       style:UIAlertActionStyleCancel
                                                                     handler:nil];
                
                [self showAlertWithTitle:NSLocalizedString(@"Update Available", nil)
                                 message:NSLocalizedString(@"An update is available. Would you like to update to the latest version?", nil)
                                 actions:@[updateAction, cancelAction]];

                self.optionalUpdateShown = YES;
            }
        }
    }
}

- (void)openUpdateURL {
    NSDictionary *settings = [self getPersistedSettings];
    NSString *updateURLString = [settings objectForKey:kManUpAppUpdateURL];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:updateURLString]];
}

+ (id)settingForKey:(NSString *)key {
    return [[[NSUserDefaults standardUserDefaults] valueForKey:kManUpSettings] valueForKey:key];
}

+ (NSComparisonResult)compareVersion:(NSString *)firstVersion toVersion:(NSString *)secondVersion {
    if ([firstVersion isEqualToString:secondVersion]) {
        return NSOrderedSame;
    }
    
    NSArray *firstVersionComponents = [firstVersion componentsSeparatedByString:@"."];
    NSArray *secondVersionComponents = [secondVersion componentsSeparatedByString:@"."];
    
    for (NSInteger index = 0; index < MAX([firstVersionComponents count], [secondVersionComponents count]); index++) {
        NSInteger firstComponent = (index < [firstVersionComponents count]) ? [firstVersionComponents[index] integerValue] : 0;
        NSInteger secondComponent = (index < [secondVersionComponents count]) ? [secondVersionComponents[index] integerValue] : 0;
        
        if (firstComponent < secondComponent) {
            return NSOrderedAscending;
            
        } else if (firstComponent > secondComponent) {
            return NSOrderedDescending;
        }
    }
    
    return NSOrderedSame;
}

@end
