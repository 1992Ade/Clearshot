#import "FBConfigViewController.h"
#import "FBButtonConfig.h"
#import "FBAppearance.h"

typedef NS_ENUM(NSInteger, Section) {
    SectionEnabled = 0,
    SectionDisabled,
    SectionAppearance,
    SectionCount
};

typedef NS_ENUM(NSInteger, AppearanceRow) {
    AppearanceRowColor = 0,
    AppearanceRowOpacity,
    AppearanceRowCount
};

@interface FBConfigViewController () <UITableViewDataSource, UITableViewDelegate, UIColorPickerViewControllerDelegate>
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *enabled;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *disabled;
@property (strong, nonatomic) UISlider *opacitySlider;
@property (nonatomic) BOOL dirty;
@end

@implementation FBConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Boutons";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    [self loadState];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.allowsSelectionDuringEditing = YES;
    self.table.editing = YES;
    [self.view addSubview:self.table];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self save];
    if (self.dirty && [self.delegate respondsToSelector:@selector(configViewControllerDidChange:)]) {
        [self.delegate configViewControllerDidChange:self];
    }
}

#pragma mark - state

- (void)loadState {
    self.enabled = [[FBButtonConfig enabledOrderedButtons] mutableCopy];
    NSMutableArray *dis = [NSMutableArray new];
    for (NSNumber *t in [FBButtonConfig allButtons]) {
        if (![self.enabled containsObject:t]) [dis addObject:t];
    }
    self.disabled = dis;
}

- (void)save {
    [FBButtonConfig setEnabledOrderedButtons:self.enabled];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return SectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SectionEnabled:    return self.enabled.count;
        case SectionDisabled:   return self.disabled.count;
        case SectionAppearance: return AppearanceRowCount;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SectionEnabled:    return @"Actifs (glissez pour réordonner)";
        case SectionDisabled:   return @"Désactivés (tap + pour activer)";
        case SectionAppearance: return @"Apparence de la barre";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == SectionEnabled)
        return @"L'ordre ci-dessus est celui dans lequel les boutons apparaîtront sur la barre, de gauche à droite.";
    if (section == SectionAppearance)
        return @"La transparence s'applique à la couleur de fond. Les icônes des boutons restent blanches.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SectionAppearance) return [self appearanceCellForRow:ip.row];

    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    NSArray *arr = ip.section == SectionEnabled ? self.enabled : self.disabled;
    FBButtonType t = (FBButtonType)[arr[ip.row] integerValue];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@",
                           [FBButtonConfig iconForType:t],
                           [FBButtonConfig labelForType:t]];
    cell.detailTextLabel.text = [self descriptionForType:t];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (NSString *)descriptionForType:(FBButtonType)t {
    switch (t) {
        case FBButtonTypeHome:        return @"Simule un appui sur le bouton Home";
        case FBButtonTypeBack:        return @"Edge-swipe depuis le bord gauche";
        case FBButtonTypeAppSwitcher: return @"Ouvre le sélecteur d'applications";
        case FBButtonTypeCapture:     return @"Capture d'écran sans la barre";
    }
    return @"";
}

#pragma mark - appearance cells

- (UITableViewCell *)appearanceCellForRow:(NSInteger)row {
    if (row == AppearanceRowColor) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"color"];
        cell.textLabel.text = @"Couleur";
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
        swatch.backgroundColor = [FBAppearance barColor];
        swatch.layer.cornerRadius = 16;
        swatch.layer.borderColor = [UIColor separatorColor].CGColor;
        swatch.layer.borderWidth = 1.0;
        cell.accessoryView = swatch;
        cell.editingAccessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    // Opacity slider row
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"opacity"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = @"Transparence";

    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 30)];
    self.opacitySlider.minimumValue = 0.1;
    self.opacitySlider.maximumValue = 1.0;
    self.opacitySlider.value = (float)[FBAppearance barOpacity];
    [self.opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = self.opacitySlider;
    cell.editingAccessoryView = self.opacitySlider;
    return cell;
}

- (void)opacityChanged:(UISlider *)s {
    [FBAppearance setBarOpacity:s.value];
    self.dirty = YES;
}

#pragma mark - Row selection → color picker

- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SectionAppearance && ip.row == AppearanceRowColor) return ip;
    return nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != SectionAppearance || ip.row != AppearanceRowColor) return;

    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.selectedColor = [FBAppearance barColor];
        picker.supportsAlpha = NO;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [FBAppearance setBarColor:viewController.selectedColor];
    self.dirty = YES;
    NSIndexPath *ip = [NSIndexPath indexPathForRow:AppearanceRowColor inSection:SectionAppearance];
    [self.table reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:AppearanceRowColor inSection:SectionAppearance]] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - editing (reorder + add/remove) — buttons sections only

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == SectionEnabled && self.enabled.count > 1;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == SectionEnabled || ip.section == SectionDisabled;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == SectionEnabled) return UITableViewCellEditingStyleDelete;
    if (ip.section == SectionDisabled) return UITableViewCellEditingStyleInsert;
    return UITableViewCellEditingStyleNone;
}

- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip {
    return @"Retirer";
}

- (BOOL)tableView:(UITableView *)tv shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == SectionEnabled || ip.section == SectionDisabled;
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    if (from.section != SectionEnabled || to.section != SectionEnabled) return;
    NSNumber *item = self.enabled[from.row];
    [self.enabled removeObjectAtIndex:from.row];
    [self.enabled insertObject:item atIndex:to.row];
    self.dirty = YES;
}

- (NSIndexPath *)tableView:(UITableView *)tv targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section != SectionEnabled) {
        return [NSIndexPath indexPathForRow:(NSInteger)self.enabled.count - 1 inSection:SectionEnabled];
    }
    return to;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    self.dirty = YES;
    if (style == UITableViewCellEditingStyleDelete && ip.section == SectionEnabled) {
        NSNumber *item = self.enabled[ip.row];
        [self.enabled removeObjectAtIndex:ip.row];
        [self.disabled addObject:item];
        [tv beginUpdates];
        [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tv insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)self.disabled.count - 1 inSection:SectionDisabled]]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
        [tv endUpdates];
    } else if (style == UITableViewCellEditingStyleInsert && ip.section == SectionDisabled) {
        NSNumber *item = self.disabled[ip.row];
        [self.disabled removeObjectAtIndex:ip.row];
        [self.enabled addObject:item];
        [tv beginUpdates];
        [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tv insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)self.enabled.count - 1 inSection:SectionEnabled]]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
        [tv endUpdates];
    }
}

@end
