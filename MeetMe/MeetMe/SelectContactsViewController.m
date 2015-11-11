//
//  SelectContactsViewController.m
//  MeetMe
//
//  Created by Anas Bouzoubaa on 28/10/15.
//  Copyright © 2015 Anas Bouzoubaa. All rights reserved.
//

#import "SelectContactsViewController.h"
#import <Contacts/Contacts.h>
#import <Parse/Parse.h>
#import <SVProgressHUD/SVProgressHUD.h>

@interface SelectContactsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (strong, nonatomic) IBOutlet UITableView *myTableView;

@property (strong, nonatomic) NSMutableArray *contactsArray;
@property (strong, nonatomic) NSMutableArray *notInAppArray;
@property (strong, nonatomic) NSMutableArray *friends;
@property (strong, nonatomic) CNContactStore *store;

@end

@implementation SelectContactsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.contactsArray = [[NSMutableArray alloc] init];
    self.notInAppArray = [[NSMutableArray alloc] init];
    self.friends = [[NSMutableArray alloc] init];
}

- (void)viewDidAppear:(BOOL)animated
{
    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack];
    [SVProgressHUD showWithStatus:@"Loading Contacts"];
    
    self.store = [[CNContactStore alloc] init];
    [self.store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
    
        // Return early if not granted access
        //TODO: Alert user
        if (!granted) return;

        // Fetch contacts
        [self fetchContacts];
    }];
}

/**
 *  Fetches contacts from CNContactStore
 *  and adds them in _contactsArray to be displayed
 *  in the tableview.
 */
- (void)fetchContacts
{
    // Fetch all contacts
    NSPredicate *predicate = [CNContact predicateForContactsInContainerWithIdentifier:self.store.defaultContainerIdentifier];
    NSArray *keys = [NSArray arrayWithObjects:
                             CNContactGivenNameKey,
                             CNContactFamilyNameKey,
                             CNContactPhoneNumbersKey,
                             CNContactThumbnailImageDataKey, nil];
    
    // Go back to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Store all contacts
        _contactsArray = [NSMutableArray arrayWithArray:[self.store unifiedContactsMatchingPredicate:predicate keysToFetch:keys error:nil]];
        
        // Remove contacts with no name
        NSMutableArray *toDelete = [NSMutableArray array];
        for (id object in _contactsArray) {
            if ([[object givenName] length] == 0) {
                [toDelete addObject:object];
            }
        }
        [_contactsArray removeObjectsInArray:toDelete];
        
        // ... and sort them
        _contactsArray = [NSMutableArray arrayWithArray:[_contactsArray sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[a givenName] compare:[b givenName]];
        }]];
        
        [_myTableView reloadData];
        
        // Send Parse the phone numbers
        [self pushContactsToParse];
    });
}

- (void) pushContactsToParse
{
    // Flatten phone numbers first
    // by removing +, (, ), and '1' for US phones
    NSMutableArray *numbers = [[NSMutableArray alloc] init];
    for (CNContact *contact in self.contactsArray) {
        if (contact.phoneNumbers.count > 0) {
            for (CNLabeledValue *labeledValue in contact.phoneNumbers) {
                CNPhoneNumber *number = [labeledValue value];
                
                // Strip off unneeded characters
                NSString *parsedNum = [[[number stringValue] componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                
                if ([parsedNum length] > 0) {
                    // and the starting '1' of US phone numbers
                    if ([parsedNum characterAtIndex:0] == '1') parsedNum = [parsedNum substringFromIndex:1];
                    // ...then added to object of phone numbers to send to Parse
                    [numbers addObject:parsedNum];
                }
            }
        }
    }
    
    [PFCloud callFunctionInBackground:@"getCommonContacts" withParameters:@{@"phoneNumbers":numbers} block:^(id  _Nullable object, NSError * _Nullable error) {
        
        [SVProgressHUD dismiss];
        
        // TODO: Handle Error
        if (error) return;
        
        // Add contacts in _friends array and reload table
        if ([(NSArray*)object count] > 0) {
            _friends = [NSMutableArray arrayWithArray:object];
            // ... and sort them
            _friends = [NSMutableArray arrayWithArray:[_friends sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"]];
            }]];
            [_myTableView reloadData];
        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

//------------------------------------------------------------------------------------------
#pragma mark - UITableView -
//------------------------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return self.friends.count;
    else return self.contactsArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Dequeue prototype cell
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"contactCell"];
    
    UILabel *nameLabel = (UILabel*)[cell viewWithTag:101];
    UIImageView *profileImageView = (UIImageView*)[cell viewWithTag:100];
    [profileImageView.layer setCornerRadius:(profileImageView.bounds.size.width/2)];
    [profileImageView setClipsToBounds:YES];
    
    // Section 0: Contacts from Parse
    if (indexPath.section == 0) {

        if (self.friends.count > 0) {
            
            // Contact to display
            NSDictionary *contact = [self.friends objectAtIndex:indexPath.row];
            profileImageView.image = [UIImage imageWithData:[(PFFile*)[contact objectForKey:@"profilePicture"] getData]];
            nameLabel.text = [[contact objectForKey:@"name"] capitalizedString];
            
            // Fetch image on background thread
//            [(PFFile*)[contact objectForKey:@"profilePicture"] getDataInBackgroundWithBlock:^(NSData * _Nullable data, NSError * _Nullable error) {
//                cell.imageView.image = [UIImage imageWithData:data];
//            } progressBlock:nil];
        }
        
    // Section 1: Contacts from Address Book
    } else {
        
        nameLabel.text = [[self.contactsArray objectAtIndex:indexPath.row] givenName];
        UIImage *image = [UIImage imageWithData:[[self.contactsArray objectAtIndex:indexPath.row] valueForKey:@"thumbnailImageData"]];
        profileImageView.image = image ?: [UIImage imageNamed:@"No-Avatar"];
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        return self.friends.count > 0 ? @"Contacts in Rendez-Vous" : @"";
    } else {
        return self.contactsArray.count > 0 ? @"Contacts on Phone" : @"";
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
