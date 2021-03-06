//
//  SenseConnector.m
//  SenseConnector
//
//  Created by aimservices on 19.05.14.
//
//

#import "SenseConnector.h"
#import <sense/SFKInitializer.h>
#import <sense/SFKSessionService.h>
#import <sense/SFKNotificationName.h>

const int LOGIN_OK               = 0;
const int LOGIN_PINCODE_REQUIRED = 1;
const int LOGIN_UPDATE_AVAILABLE = 2;
const int SESSION_EXPIRED        = 3;
const int SESSION_LOCKED         = 4;

typedef void (^LoginBlock)(NSError* error, SenseConnector* connector, CDVInvokedUrlCommand* command);
LoginBlock loginCallback = ^(NSError* error, SenseConnector* connector, CDVInvokedUrlCommand* command) {
    NSLog(@"\t%@", @"Inside callback");
    CDVPluginResult* loginResult = nil;
    if (error) {
        NSString* errorMsg = [[error userInfo] objectForKey:@"NSLocalizedDescription"];
        NSString* message = [NSString stringWithFormat:@"Unable to login.\nError: %@", errorMsg];
        NSLog(@"\t%@", message);
        
        NSDictionary* json = [connector createJSON:@"ERR_LOGIN_FAILED" withMessage:errorMsg];
        loginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:json];
    } else {
        NSString* message = @"Successfully logged-in.";
        NSLog(@"\t%@", message);
        
        NSDictionary* json = [connector createJSON:[NSNumber numberWithInt:LOGIN_OK] withMessage:nil];
        loginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:json];
        [loginResult setKeepCallbackAsBool:TRUE];
    }
    connector.loginCommmandId = command.callbackId;
    [connector.commandDelegate sendPluginResult:loginResult callbackId:command.callbackId];
};

@interface SenseConnector ()
- (BOOL)isEnrolled:(NSString*)username;

- (void)privacySettings;
- (void)clearTraces;
- (NSString*)decodeB64:(NSString*)value;
@end

@implementation SenseConnector

- (void)pluginInitialize {
    NSLog(@"SenseConnector plugin initialized");
    [[SFKInitializer sharedInitializer] initializeSenseWithSecurityURL:SECURITY_SERVER_URL proxyURL:APP_SERVER_URL errorBlock:^(NSError* error) {
        if (error) {
            NSString* errorMsg = [[error userInfo] objectForKey:@"NSLocalizedDescription"];
            NSString* message = [NSString stringWithFormat:@"Something went wrong here.\nError: %@", errorMsg];
            NSLog(@"\t%@", message);
        }
    }];
    
    /* SENSE:
     * When a user authenticates himself on a server, Sense framework will receive the security settings set by the admin.
     * By registering to these two notifications, you will know when the inactivity timers fire
     * and when the session is over. You have to implement how these notifications are handled on your application.
     */
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(displayInactivityVC) name:SFK_INACTIVITY_TIMEOUT_NOTIFICATION object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionTimeout) name:SFK_OFFLINE_TIMEOUT_NOTIFICATION object:nil];
    
}

- (void)displayInactivityVC {
    NSLog(@"Sense inactivity time-out notification");
    NSDictionary* json = [self createJSON:[NSNumber numberWithInt:SESSION_LOCKED] withMessage:nil];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:json] callbackId:self.loginCommmandId];
}

- (void)sessionTimeout {
    NSLog(@"Sense session time-out notification");
    NSDictionary* json = [self createJSON:[NSNumber numberWithInt:SESSION_EXPIRED] withMessage:nil];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:json] callbackId:self.loginCommmandId];
}

- (BOOL)isEnrolled:(NSString*)username {
    NSArray* enrolledUsers = [SFKSessionService alreadyEnrolledUsers];
    return ([enrolledUsers containsObject:username]);
}

- (NSDictionary*)createJSON:(NSObject*)code withMessage:(NSString*)message {
    NSString* codeStr = [NSString stringWithFormat:@"%@", code];
    NSDictionary* jsonObj = [[NSDictionary alloc] initWithObjectsAndKeys:codeStr, @"code", nil];
    if (message != nil) {
        jsonObj = [NSMutableDictionary dictionaryWithDictionary:jsonObj];
        [jsonObj setValue:message forKey:@"message"];
    }
    return jsonObj;
}

- (void)updateApp:(CDVInvokedUrlCommand*)command {
    NSDictionary* arguments = [command argumentAtIndex:0];
    NSString* url = [arguments valueForKey:@"url"];
    NSLog(@"Updating application from %@", url);
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Application update"
                                                    message:[NSString stringWithFormat:@"Url: %@", url]
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
    
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (void)exitApp:(CDVInvokedUrlCommand*)command {
    exit(0);
}

- (void)login:(CDVInvokedUrlCommand*)command {
    NSDictionary* arguments = [command argumentAtIndex:0];
    NSString* username = [arguments valueForKey:@"username"];
    NSString* password = [self decodeB64:[arguments valueForKey:@"password"]];

    NSLog(@"Logging in to Sense\n%@", [NSString stringWithFormat:@"Command: %@", command]);
    if ([self isEnrolled:username]) {
        // call createSessionWithUsername only if deviced is enrolled
        [SFKSessionService createSessionWithUsername:username password:password errorBlock:^(NSError* error){
            loginCallback(error, self, command);
        }];
    } else {
        NSString* message = @"Unable to login.\nError: You need to enroll a user first";
        NSLog(@"\t%@", message);
        
        NSDictionary* json = [self createJSON:[NSNumber numberWithInt:LOGIN_PINCODE_REQUIRED] withMessage:nil];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:json] callbackId:command.callbackId];
    }
}

- (void)enroll:(CDVInvokedUrlCommand*)command {
    NSDictionary* arguments = [command argumentAtIndex:0];
    NSString* username = [arguments valueForKey:@"username"];
    NSString* password = [self decodeB64:[arguments valueForKey:@"password"]];
    NSString* pincode = [arguments valueForKey:@"pincode"];
    NSLog(@"Logging in to Sense\n%@", [NSString stringWithFormat:@"Command: %@", command]);
    [SFKSessionService enrollUsername:username password:password pin:pincode errorBlock:^(NSError* error) {
        loginCallback(error, self, command);
    }];
}

- (void)dispose
{
    // @todo: [self privacySettings];
    [super dispose];
}

- (void)changePassword:(CDVInvokedUrlCommand*)command {
    NSDictionary* arguments = [command argumentAtIndex:0];
    NSString* username = [arguments valueForKey:@"username"];
    NSString* oldPassword = [self decodeB64:[arguments valueForKey:@"oldPassword"]];
    NSString* newPassword = [self decodeB64:[arguments valueForKey:@"newPassword"]];
    NSLog(@"Changing password \n%@", [NSString stringWithFormat:@"Command: %@", command]);
    [SFKSessionService changePassword:oldPassword withNewPassword:newPassword forUsername:username errorBlock:^(NSError* error) {
        loginCallback(error, self, command);
    }];
}

- (void)privacySettings {
    // Clearing cache Memory
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"WebKitCacheModelPreferenceKey"];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"WebKitOfflineWebApplicationCacheEnabled"];
    [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"WebKitLocalStorageDatabasePathPreferenceKey"];
    [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"WebKitDiskImageCacheSavedCacheDirectory"];
    [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"WebDatabaseDirectory"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [[NSURLCache sharedURLCache] setMemoryCapacity:0];
    
    [self clearTraces];
}

- (void)clearTraces {
    [self.webView stringByEvaluatingJavaScriptFromString:@"localStorage.clear();"];
    [self.webView stringByEvaluatingJavaScriptFromString:@"sessionStorage.clear();"];
    
    // Deleting all the cookies
    for(NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
    }
}

- (NSString*)decodeB64:(NSString*)value {
    NSData* data = [[NSData alloc] initWithBase64EncodedString:value options:0];
    NSString* decoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return decoded;
}

@end
