# NSWindow Styles
const NSBorderlessWindowMask             = 0
const NSTitledWindowMask                 = 1 << 0
const NSClosableWindowMask               = 1 << 1
const NSMiniaturizableWindowMask         = 1 << 2
const NSResizableWindowMask              = 1 << 3
const NSTexturedBackgroundWindowMask     = 1 << 8
const NSUnifiedTitleAndToolbarWindowMask = 1 << 12

# NSWindow Backing
const NSBackingStoreRetained      = 0
const NSBackingStoreNonretained   = 1
const NSBackingStoreBuffered      = 2

# NSWindow collection behaviours
const NSWindowCollectionBehaviorDefault  = 0
const NSWindowCollectionBehaviorCanJoinAllSpaces  = 1 << 0
const NSWindowCollectionBehaviorMoveToActiveSpace  = 1 << 1
const NSWindowCollectionBehaviorManaged  = 1 << 2
const NSWindowCollectionBehaviorTransient  = 1 << 3
const NSWindowCollectionBehaviorStationary  = 1 << 4
const NSWindowCollectionBehaviorParticipatesInCycle  = 1 << 5
const NSWindowCollectionBehaviorIgnoresCycle  = 1 << 6
const NSWindowCollectionBehaviorFullScreenPrimary  = 1 << 7
const NSWindowCollectionBehaviorFullScreenAuxiliary  = 1 << 8

# NSApplication Activation policies
const NSApplicationActivationPolicyRegular    = 0
const NSApplicationActivationPolicyAccessory  = 1
const NSApplicationActivationPolicyProhibited = 2

# NSApplication presentation styles
const NSApplicationPresentationDefault                    = 0
const NSApplicationPresentationAutoHideDock               = 1 <<  0
const NSApplicationPresentationHideDock                   = 1 <<  1
const NSApplicationPresentationAutoHideMenuBar            = 1 <<  2
const NSApplicationPresentationHideMenuBar                = 1 <<  3
const NSApplicationPresentationDisableAppleMenu           = 1 <<  4
const NSApplicationPresentationDisableProcessSwitching    = 1 <<  5
const NSApplicationPresentationDisableForceQuit           = 1 <<  6
const NSApplicationPresentationDisableSessionTermination  = 1 <<  7
const NSApplicationPresentationDisableHideApplication     = 1 <<  8
const NSApplicationPresentationDisableMenuBarTransparency = 1 <<  9
const NSApplicationPresentationFullScreen                 = 1 << 10
const NSApplicationPresentationAutoHideToolbar            = 1 << 11
