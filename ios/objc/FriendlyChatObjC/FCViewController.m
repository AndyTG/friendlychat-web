//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "AppState.h"
#import "Constants.h"
#import "FCViewController.h"

@import FirebaseDatabase;
@import FirebaseApp;
@import FirebaseAuth;
@import Firebase.AdMob;
@import Firebase.Config;
@import Firebase.Core;
@import Firebase.CrashReporting;

@interface FCViewController ()<UITableViewDataSource, UITableViewDelegate,
UITextFieldDelegate> {
  int _msglength;
  FirebaseHandle _refHandle;
  UInt32 _userInt;
}

@property(nonatomic, weak) IBOutlet UITextField *textField;
@property(nonatomic, weak) IBOutlet UIButton *sendButton;

@property(nonatomic, weak) IBOutlet GADBannerView *banner;
@property(nonatomic, weak) IBOutlet UITableView *clientTable;

@property (strong, nonatomic) Firebase *ref;
@property (strong, nonatomic) NSMutableArray<FDataSnapshot *> *messages;

@end

@implementation FCViewController

- (IBAction)didSendMessage:(UIButton *)sender {
  [self textFieldShouldReturn:_textField];
}

- (IBAction)didPressCrash:(id)sender {
  FCRLog(@"Cause Crash button clicked");
  assert(NO);
}

- (void)viewDidLoad {
  [super viewDidLoad];

  _ref = [[Firebase alloc] initWithUrl:[FIRContext sharedInstance].serviceInfo.databaseURL];
  _userInt = arc4random();
  _msglength = 10;
  _messages = [[NSMutableArray alloc] init];

  [self loadAd];
  [_clientTable registerClass:UITableViewCell.self forCellReuseIdentifier:@"tableViewCell"];
  [self fetchConfig];

  // Log that the view did load, FCRNSLog is used here so the log message will be
  // shown in the console output. If FCRLog is used the message is not shown in
  // the console output.
  FCRNSLog(@"View loaded");
}

- (void)loadAd {
  self.banner.adUnitID = [FIRContext sharedInstance].adUnitIDForBannerTest;
  self.banner.rootViewController = self;
  [self.banner loadRequest:[GADRequest request]];
}

- (void)fetchConfig {
  RCNDefaultConfigCompletion completion = ^void(RCNConfig *config, RCNConfigStatus status, NSError *error) {
    if (error) {
      // There has been an error fetching the config
      NSLog(@"Error fetching config: %@", error.localizedDescription);
    } else {
      // Parse your config data
      _msglength = [[config numberForKey:@"friendly_msg_length" defaultValue:[NSNumber numberWithInt:10]] intValue];
      NSLog(@"Friendly msg length config: %d", _msglength);
    }
  };

  NSDictionary *customVariables = @{@"build": @"dev"};
  // 43200 secs = 12 hours
  [RCNConfig fetchDefaultConfigWithExpirationDuration:43200
                                      customVariables:customVariables
                                    completionHandler:completion];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(nonnull NSString *)string {
  NSString *text = textField.text;
  if (!text) {
    return YES;
  }
  long newLength = text.length + string.length - range.length;
  return (newLength <= _msglength);
}

- (void)viewWillAppear:(BOOL)animated {
  [_messages removeAllObjects];
  // Listen for new messages in the Firebase database
  _refHandle = [[_ref childByAppendingPath:@"messages"] observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot *snapshot) {
    [_messages addObject:snapshot];
    [_clientTable insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:_messages.count-1 inSection:0]] withRowAnimation: UITableViewRowAnimationAutomatic];
  }];
}

- (void)viewWillDisappear:(BOOL)animated {
  [_ref removeObserverWithHandle:_refHandle];
}

// UITableViewDataSource protocol methods
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return [_messages count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
  // Dequeue cell
  UITableViewCell *cell = [_clientTable dequeueReusableCellWithIdentifier:@"tableViewCell" forIndexPath:indexPath];

  // Unpack message from Firebase DataSnapshot
  FDataSnapshot *messageSnapshot = _messages[indexPath.row];
  NSDictionary<NSString *, NSString *> *message = messageSnapshot.value;
  NSString *name = message[MessageFieldsname];
  NSString *text = message[MessageFieldstext];
  cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", name, text];
  cell.imageView.image = [UIImage imageNamed: @"ic_account_circle"];
  NSString *photoUrl = message[MessageFieldsphotoUrl];
  if (photoUrl) {
    NSURL *url = [NSURL URLWithString:photoUrl];
    if (url) {
      NSData *data = [NSData dataWithContentsOfURL:url];
      if (data) {
        cell.imageView.image = [UIImage imageWithData:data];
      }
    }
  }

  return cell;
}

// UITextViewDelegate protocol methods
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
  data[MessageFieldstext] = textField.text;
  data[MessageFieldsname] = [NSString stringWithFormat:@"User%d", (unsigned int)_userInt];
  NSString *user = [AppState sharedInstance].displayName;
  if (user) {
    data[MessageFieldsname] = user;
  }
  NSURL *photoUrl = AppState.sharedInstance.photoUrl;
  if (photoUrl) {
    data[MessageFieldsphotoUrl] = [photoUrl absoluteString];
  }

  // Push data to Firebase Database
  [[[_ref childByAppendingPath:@"messages"] childByAutoId] setValue:data];
  textField.text = @"";
  return YES;
}

- (IBAction)signOut:(UIButton *)sender {
  FIRAuth *firebaseAuth = [FIRAuth auth];
  NSError *signOutError;
  BOOL status = [firebaseAuth signOut:&signOutError];
  if (!status) {
    NSLog(@"Error signing out: %@", signOutError);
    return;
  }
  [AppState sharedInstance].signedIn = false;
  [self performSegueWithIdentifier:SeguesFpToSignIn sender:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDestructive handler:nil];
    [alert addAction:dismissAction];
    [self presentViewController:alert animated: true completion: nil];
  });
}

@end
