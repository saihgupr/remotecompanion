#import <UIKit/UIKit.h>

@interface RCHAEntityPickerViewController : UITableViewController
@property (nonatomic, copy) void (^onEntitySelected)(NSString *command);

// An existing "ha ..." command being edited. The picker marks its entity in the list and,
// with opensOnCurrentChoices, opens straight on that entity's action choices with the
// current service ticked.
@property (nonatomic, copy) NSString *editingCommand;
@property (nonatomic, assign) BOOL opensOnCurrentChoices;

// The entity and domain.service an "ha ..." command calls (light.bedroom, light.turn_on).
// Returns NO for raw commands and anything that isn't an entity action.
+ (BOOL)parseCommand:(NSString *)command entityId:(NSString **)entityId service:(NSString **)service;

// "light.bedroom_lamp" -> "Bedroom Lamp"
+ (NSString *)friendlyNameForEntity:(NSString *)entityId;
@end
