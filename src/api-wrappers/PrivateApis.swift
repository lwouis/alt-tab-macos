import Cocoa

// Private APIs are APIs that we can build the app against, but they are not supported or documented by Apple
// We can see their names as symbols in the SDK (see https://github.com/lwouis/MacOSX-SDKs)
// However their full signature is a best-effort of retro-engineering
// Very little information is available about private APIs. I tried to document them as much as possible here
// Some links:
// * Webkit repo: https://github.com/WebKit/webkit/blob/master/Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h
// * Alt-tab-macos issue: https://github.com/lwouis/alt-tab-macos/pull/87#issuecomment-558624755
// * Github repo with retro-engineered internals: https://github.com/NUIKit/CGSInternal

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    // on a retina display, 1px is spread on 4px, so nominalResolution is 1/4 of bestResolution
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
}

enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

// returns the connection to the WindowServer. This connection ID is required when calling other APIs
// * macOS 10.10+
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// returns an array of CGImage of the windows which ID is given as `windowList`. `windowList` is supposed to be an array of IDs but in my test on High Sierra, the function ignores other IDs than the first, and always returns the screenshot of the first window in the array
// * performance: the `HW` in the name seems to imply better performance, and it was observed by some contributors that it seems to be faster (see https://github.com/lwouis/alt-tab-macos/issues/45) than other methods
// * quality: medium
// * minimized windows: yes
// * windows in other spaces: yes
// * offscreen content: no
// * macOS 10.10+
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>

// returns the connection ID for the provided window
// * macOS 10.10+
@_silgen_name("CGSGetWindowOwner") @discardableResult
func CGSGetWindowOwner(_ cid: CGSConnectionID, _ wid: CGWindowID, _ windowCid: inout CGSConnectionID) -> CGError

// returns the PSN for the provided connection ID
// * macOS 10.10+
@_silgen_name("CGSGetConnectionPSN") @discardableResult
func CGSGetConnectionPSN(_ cid: CGSConnectionID, _ psn: inout ProcessSerialNumber) -> CGError

// returns an array of displays (as NSDictionary) -> each having an array of spaces (as NSDictionary) at the "Spaces" key; each having a space ID (as UInt64) at the "id64" key
// * macOS 10.10+
// /!\ only returns correct values if the user has checked the checkbox in Preferences > Mission Control > "Displays have separate Spaces"
// See this example with 2 monitors (1 laptop internal + 1 external):
// * Output with "Displays have separate Spaces" checked:
//   [{
//       "Current Space" =     {
//           ManagedSpaceID = 4;
//           id64 = 4;
//           type = 0;
//           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//       };
//       "Display Identifier" = "6FBB92D9-84CE-8D20-C114-3B1052DD9529";
//       Spaces =     (
//           {
//               ManagedSpaceID = 4;
//               id64 = 4;
//               type = 0;
//               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//           }
//       );
//   }, {
//       "Current Space" =     {
//           ManagedSpaceID = 5;
//           id64 = 5;
//           type = 0;
//           uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
//       };
//       "Display Identifier" = "BB2327F9-3D4F-FD8F-A0EA-B9745A0B818F";
//       Spaces =     (
//           {
//               ManagedSpaceID = 5;
//               id64 = 5;
//               type = 0;
//               uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
//           }
//       );
//   }]
// * Output with "Displays have separate Spaces" unchecked:
//   [{
//       "Current Space" =     {
//           ManagedSpaceID = 4;
//           id64 = 4;
//           type = 0;
//           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//       };
//       "Display Identifier" = Main;
//       Spaces =     (
//           {
//               ManagedSpaceID = 4;
//               id64 = 4;
//               type = 0;
//               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//           }
//       );
//   }]
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

struct CGSCopyWindowsOptions: OptionSet {
    let rawValue: Int
    static let invisible1 = CGSCopyWindowsOptions(rawValue: 1 << 0)
    // retrieves windows when their app is assigned to All Spaces, and windows at ScreenSaver level 1000
    static let screenSaverLevel1000 = CGSCopyWindowsOptions(rawValue: 1 << 1)
    static let invisible2 = CGSCopyWindowsOptions(rawValue: 1 << 2)
    static let unknown1 = CGSCopyWindowsOptions(rawValue: 1 << 3)
    static let unknown2 = CGSCopyWindowsOptions(rawValue: 1 << 4)
    static let desktopIconWindowLevel2147483603 = CGSCopyWindowsOptions(rawValue: 1 << 5)
}

struct CGSCopyWindowsTags: OptionSet {
    let rawValue: Int
    static let level0 = CGSCopyWindowsTags(rawValue: 1 << 0)
    static let noTitleMaybePopups = CGSCopyWindowsTags(rawValue: 1 << 1)
    static let unknown1 = CGSCopyWindowsTags(rawValue: 1 << 2)
    static let mainMenuWindowAndDesktopIconWindow = CGSCopyWindowsTags(rawValue: 1 << 3)
    static let unknown2 = CGSCopyWindowsTags(rawValue: 1 << 4)
}

// returns an array of window IDs (as UInt32) for the space(s) provided as `spaces`
// the elements of the array are ordered by the z-index order of the windows in each space, with some exceptions where spaces mix
// * macOS 10.10+
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int, _ setTags: inout Int, _ clearTags: inout Int) -> CFArray

// returns the current space ID on the provided display UUID
// * macOS 10.10+
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> CGSSpaceID

// adds the provided windows to the provided spaces
// * macOS 10.10-12.2
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// remove the provided windows from the provided spaces
// * macOS 10.10-12.2
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// Move the given windows (CGWindowIDs) to the given space (CGSSpaceID)
// doesn't move fullscreen'ed windows
// * macOS 10.10+
@_silgen_name("CGSMoveWindowsToManagedSpace")
func CGSMoveWindowsToManagedSpace(_ cid: CGSConnectionID, _ windows: NSArray, _ space: CGSSpaceID) -> Void

// focuses the front process
// * macOS 10.12+
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID, _ mode: SLPSMode.RawValue) -> CGError

// sends bytes to the WindowServer
// more context: https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
// * macOS 10.12+
@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: inout UInt8) -> CGError

// returns the CGWindowID of the provided AXUIElement
// * macOS 10.10+
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: inout CGWindowID) -> AXError

// returns the provided CGWindow property for the provided CGWindowID
// * macOS 10.10+
@_silgen_name("CGSCopyWindowProperty") @discardableResult
func CGSCopyWindowProperty(_ cid: CGSConnectionID, _ wid: CGWindowID, _ property: CFString, _ value: inout CFTypeRef?) -> CGError

enum CGSSpaceMask: Int {
    case current = 5
    case other = 6
    case all = 7
}

// get the CGSSpaceIDs for the given windows (CGWindowIDs)
// * macOS 10.10+
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: CGSSpaceMask.RawValue, _ wids: CFArray) -> CFArray

// returns window level (see definition in CGWindowLevel.h) of provided window
// * macOS 10.10+
@_silgen_name("CGSGetWindowLevel") @discardableResult
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: inout CGWindowLevel) -> CGError

// returns status of the checkbox in System Preferences > Security & Privacy > Privacy > Screen Recording
// returns 1 if checked or 0 if unchecked; also prompts the user the first time if unchecked
// the return value will be the same during the app lifetime; it will not reflect the actual status of the checkbox
@_silgen_name("SLSRequestScreenCaptureAccess") @discardableResult
func SLSRequestScreenCaptureAccess() -> UInt8

// for some reason, these attributes are missing from AXAttributeConstants
let kAXFullscreenAttribute = "AXFullScreen"
let kAXStatusLabelAttribute = "AXStatusLabel"

enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6 // see keyAboveTabDependingOnInputSource
}

// enables/disables a symbolic hotkeys. These are system shortcuts such as command+tab or Spotlight
// it is possible to find all the existing hotkey IDs by using CGSGetSymbolicHotKeyValue on the first few hundred numbers
// note: the effect of enabling/disabling persists after the app is quit
@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> CGError

func setNativeCommandTabEnabled(_ isEnabled: Bool, _ hotkeys: [CGSSymbolicHotKey] = CGSSymbolicHotKey.allCases) {
    for hotkey in hotkeys {
        CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, isEnabled)
    }
}

// returns info about a given psn
// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessInformation") @discardableResult
func GetProcessInformation(_ psn: inout ProcessSerialNumber, _ info: inout ProcessInfoRec) -> OSErr
//
// returns the psn for a given pid
// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessForPID") @discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

enum CGSSpaceType: Int {
    case user = 0
    case system = 2
    case fullscreen = 4
}

// get the CGSSpaceType for a given space. Maybe useful for fullscreen windows
// * macOS 10.10+
@_silgen_name("CGSSpaceGetType")
func CGSSpaceGetType(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> CGSSpaceType


// move a window to a Space; works with fullscreen windows
// with fullscreen window, sending it back to its original state later seems to mess with macOS internals. The Space appears fully black
// this API seems unreliable to use
// the last param seem to work with 0x80007; not sure what it means
// * macOS 10.10-12.2
@_silgen_name("CGSSpaceAddWindowsAndRemoveFromSpaces")
func CGSSpaceAddWindowsAndRemoveFromSpaces(_ cid: CGSConnectionID, _ sid: CGSSpaceID, _ wid: NSArray, _ notSure: Int) -> Void

// get the display UUID with the active menubar (other menubar are dimmed)
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> ScreenUuid


// ------------------------------------------------------------
// below are some notes on some private APIs I experimented with
// ------------------------------------------------------------

//// move the windows on the given Space. Note: doesn't move fullscreen windows
//// * macOS 10.12+
//@_silgen_name("CGSMoveWorkspaceWindowList")
//func CGSMoveWorkspaceWindowList(_ cid: CGSConnectionID, _ windowList: CFArray, _ windowCount: UInt, _ sid: CGSSpaceID) -> OSStatus

//// returns true if the current screen is animating
//// useful to detect Spaces transitions, windows going fullscreen, etc
//@_silgen_name("SLSManagedDisplayIsAnimating")
//func SLSManagedDisplayIsAnimating(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> Bool

//@_silgen_name("CGSGetSymbolicHotKeyValue")
//func CGSGetSymbolicHotKeyValue(_ hotKey: Int, _ options: inout UInt32, _ keyCode: inout UInt32, _ modifiers: inout UInt32) -> CGError

//@_silgen_name("CGSIsSymbolicHotKeyEnabled")
//func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int) -> Bool

//// listen to some window server events
//// most interesting events for Mission Control seem to be [1204, 1401, 1508]. It seems that these are all the valid events, as the response is .success with these: ////        [100, 101, 102, 103, 104, 106, 107, 108, 111, 115, 116, 117, 118, 119, 120, 121, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879, 880, 881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 892, 893, 894, 895, 896, 897, 898, 899, 900, 901, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 913, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, 975, 976, 977, 978, 979, 980, 981, 982, 983, 984, 985, 986, 987, 988, 989, 990, 991, 992, 993, 994, 995, 996, 997, 998, 999, 1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209, 1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228, 1229, 1230, 1231, 1232, 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241, 1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258, 1259, 1260, 1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, 1272, 1273, 1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289, 1290, 1291, 1292, 1293, 1294, 1295, 1296, 1297, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305, 1306, 1307, 1308, 1309, 1310, 1311, 1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321, 1322, 1323, 1324, 1325, 1326, 1327, 1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, 1337, 1338, 1339, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 1353, 1354, 1355, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369, 1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385, 1386, 1387, 1388, 1389, 1390, 1391, 1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 1412, 1413, 1414, 1415, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423, 1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465, 1466, 1467, 1468, 1469, 1470, 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481, 1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 1522, 1523, 1524, 1525, 1526, 1527, 1528, 1529, 1530, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545, 1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, 1561, 1562, 1563, 1564, 1565, 1566, 1567, 1568, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583, 1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593, 1594, 1595, 1596, 1597, 1598, 1599, 1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615, 1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625, 1626, 1627, 1628, 1629, 1630, 1631, 1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641, 1642, 1643, 1644, 1645, 1646, 1647, 1648, 1649, 1650, 1651, 1652, 1653, 1654, 1655, 1656, 1657, 1658, 1659, 1660, 1661, 1662, 1663, 1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673, 1674, 1675, 1676, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 1685, 1686, 1687, 1688, 1689, 1690, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710, 1711, 1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720, 1721, 1722, 1723, 1724, 1725, 1726, 1727, 1728, 1729, 1730, 1731, 1732, 1733, 1734, 1735, 1736, 1737, 1738, 1739, 1740, 1741, 1742, 1743, 1744, 1745, 1746, 1747, 1748, 1749, 1750, 1751, 1752, 1753, 1754, 1755, 1756, 1757, 1758, 1759, 1760, 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769, 1770, 1771, 1772, 1773, 1774, 1775, 1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785, 1786, 1787, 1788, 1789, 1790, 1791, 1792, 1793, 1794, 1795, 1796, 1797, 1798, 1799, 1900, 1901, 1902, 1903, 1904, 1905, 1906, 1907, 1908, 1909, 1910, 1911, 1912, 1913, 1914, 1915, 1916, 1917, 1918, 1919, 1920, 1921, 1922, 1923, 1924, 1925, 1926, 1927, 1928, 1929, 1930, 1931, 1932, 1933, 1934, 1935, 1936, 1937, 1938, 1939, 1940, 1941, 1942, 1943, 1944, 1945, 1946, 1947, 1948, 1949, 1950, 1951, 1952, 1953, 1954, 1955, 1956, 1957, 1958, 1959, 1960, 1961, 1962, 1963, 1964, 1965, 1966, 1967, 1968, 1969, 1970, 1971, 1972, 1973, 1974, 1975, 1976, 1977, 1978, 1979, 1980, 1981, 1982, 1983, 1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030, 2031, 2032, 2033, 2034, 2035, 2036, 2037, 2038, 2039, 2040, 2041, 2042, 2043, 2044, 2045, 2046, 2047, 2048, 2049, 2050, 2051, 2052, 2053, 2054, 2055, 2056, 2057, 2058, 2059, 2060, 2061, 2062, 2063, 2064, 2065, 2066, 2067, 2068, 2069, 2070, 2071, 2072, 2073, 2074, 2075, 2076, 2077, 2078, 2079, 2080, 2081, 2082, 2083, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095, 2096, 2097, 2098, 2099]
//// example calls: `SLSRegisterNotifyProc(callbackFn2, $0, nil)` `SLSRegisterConnectionNotifyProc(cgsMainConnectionId, callbackFn1, $0, nil)`
//// more info: https://github.com/asmagill/hs._asm.undocumented.spaces/blob/0b5321fc336f75488fb4bbb524677bb8291050bd/CGSConnection.h#L153
//typealias RegisterConnectionCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, CGSConnectionID) -> Void
//@_silgen_name("SLSRegisterConnectionNotifyProc") @discardableResult
//func SLSRegisterConnectionNotifyProc(_ cid: CGSConnectionID, _ callback: RegisterConnectionCallback?, _ event: Int, _ context: UnsafeMutableRawPointer?) -> CGError
//// seems exactly equivalent to SLSRegisterConnectionNotifyProc in my test
//typealias RegisterCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
//@_silgen_name("SLSRegisterNotifyProc") @discardableResult
//func SLSRegisterNotifyProc(_ callback: RegisterCallback?, _ event: Int, _ context: UnsafeMutableRawPointer?) -> CGError
//// returns the front process PSN
//// * macOS 10.12+
//@_silgen_name("_SLPSGetFrontProcess") @discardableResult
//func _SLPSGetFrontProcess(_ psn: inout ProcessSerialNumber) -> OSStatus
//
//// returns the CGImage of the window which ID is given in `wid`
//// * performance: a bit faster than `CGWindowListCreateImage`, but still less than `CGSHWCaptureWindowList`
//// * quality: low
//// * minimized windows: yes
//// * windows in other spaces: yes
//// * offscreen content: no
//// * macOS 10.10+
//@_silgen_name("CGSCaptureWindowsContentsToRectWithOptions") @discardableResult
//func CGSCaptureWindowsContentsToRectWithOptions(_ cid: CGSConnectionID, _ wid: inout CGWindowID, _ windowOnly: Bool, _ rect: CGRect, _ options: CGSWindowCaptureOptions, _ image: inout CGImage) -> CGError
//
//// returns true is the PSNs are the same
//// * deprecated in macOS 10.9, so we have to declare it to use it in Swift
//@_silgen_name("SameProcess")
//func SameProcess(_ psn1: inout ProcessSerialNumber, _ psn2: inout ProcessSerialNumber, _ same: inout DarwinBoolean) -> Void
//
//// returns the CGRect of a window
//// * performance: it seems that this function is faster than the public API AX calls to get a window bounds
//// * minimized windows: ?
//// * windows in other spaces: ?
//// * macOS 10.12+
//@_silgen_name("CGSGetWindowBounds") @discardableResult
//func CGSGetWindowBounds(_ cid: CGSConnectionID, _ wid: inout CGWindowID, _ frame: inout CGRect) -> CGError
//
//// * deprecated in macOS 10.9, so we have to declare it to use it in Swift
//@_silgen_name("GetProcessPID")
//func GetProcessPID(_ psn: inout ProcessSerialNumber, _ pid: inout pid_t) -> Void
//
//// crashed the app with SIGSEGV
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowType") @discardableResult
//func CGSGetWindowType(_ wid: CGWindowID, _ type: inout UInt32) -> CGError
//
//// * macOS 10.12+
//@_silgen_name("CGSProcessAssignToSpace") @discardableResult
//func CGSProcessAssignToSpace(_ cid: CGSConnectionID, _ pid: pid_t, _ sid: CGSSpaceID) -> CGError
//
//// changes the active space for the display_ref (e.g. "Main"). This doesn't actually trigger the UI animation and switch to the space. It allows windows from that space to be manipulated (e.g. focused) from the current space. Very weird behaviour and graphical glitch will happen when triggering Mission Control
//// * macOS 10.10+
//@_silgen_name("CGSManagedDisplaySetCurrentSpace")
//func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ sid: CGSSpaceID) -> Void
//
//// show provided spaces on top of the current space. It show windows from the provided spaces in the current space. Very weird behaviour and graphical glitch will happen when triggering Mission Control
//// even though the windows are shown, we can't grab their AXref. The windows are only *visually* on the space
//// * macOS 10.10+
//@_silgen_name("CGSShowSpaces")
//func CGSShowSpaces(_ cid: CGSConnectionID, _ sids: NSArray) -> Void
//
//// hides provided spaces from the current space
//// * macOS 10.10+
//@_silgen_name("CGSHideSpaces")
//func CGSHideSpaces(_ cid: CGSConnectionID, _ sids: NSArray) -> Void

//
//// get space for window
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowWorkspace") @discardableResult
//func CGSGetWindowWorkspace(_ cid: CGSConnectionID, _ wid: CGWindowID, _ workspace: [Int]) -> OSStatus
//
//// returns the space uuid. Not very useful
//// * macOS 10.10+
//@_silgen_name("CGSSpaceCopyName")
//func CGSSpaceCopyName(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> CFString
//
//enum CGSWindowOrderingMode: Int {
//    case orderAbove = 1 // Window is ordered above target.
//    case orderBelow = -1 // Window is ordered below target.
//    case orderOut = 0  // Window is removed from the on-screen window list.
//}
//
//// change window order. I tried with relativeToWindow=0, and place=.orderAbove, and it does nothing
//// * macOS 10.10+
//@_silgen_name("CGSOrderWindow") @discardableResult
//func CGSOrderWindow(_ cid: CGSConnectionID, _ win: CGWindowID, _ place: CGSWindowOrderingMode.RawValue, relativeTo: CGWindowID /* can be NULL */) -> OSStatus
//
//// Get on-screen window counts and lists. With targetCID=1 -> returns []. With targetCID=0 -> crashes, with targetCID=cid -> crashes
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowList") @discardableResult
//func CGSGetWindowList(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ count: Int, _ list: [Int], _ outCount: [Int]) -> OSStatus
//
//// per-workspace window counts and lists. Can't compile on macOS 10.14 ("Undefined symbol: _CGSGetWorkspaceWindowList"). There are references of this API on the internet, but it doesn't seem to appear in any SDK though
//// * macOS 10.10+
//@_silgen_name("CGSGetWorkspaceWindowList") @discardableResult
//func CGSGetWorkspaceWindowList(_ cid: CGSConnectionID, _ workspaceNumber: CGSSpaceID, _ count: Int, _ list: [Int], _ outCount: [Int]) -> OSStatus
//
//
//// assigns a process to all spaces. This creates weird behaviours where its windows are available from all spaces
//// * macOS 10.10+
//@_silgen_name("CGSProcessAssignToAllSpaces") @discardableResult
//func CGSProcessAssignToAllSpaces(_ cid: CGSConnectionID, _ pid: pid_t) -> CGError
//
//enum SpaceManagementMode: Int {
//    case checked = 1
//    case unchecked = 0
//}
//
//// returns the status of the "Displays have separate Spaces" system Preference
//// there is a public API for that: NSScreen.screensHaveSeparateSpaces
//// * macOS 10.10+
//@_silgen_name("CGSGetSpaceManagementMode")
//func CGSGetSpaceManagementMode(_ cid: CGSConnectionID) -> SpaceManagementMode
//
//// The following function was ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
//func windowManagerDeferWindowRaise(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x09
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func windowManagerDeactivateWindow(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x02
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func windowManagerActivateWindow(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x01
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func psnEqual(_ psn1: ProcessSerialNumber, _ psn2: ProcessSerialNumber) -> Bool {
//    var psn1_ = psn1
//    var psn2_ = psn2
//
//    var same = DarwinBoolean(false)
//    SameProcess(&psn1_, &psn2_, &same)
//    return same == DarwinBoolean(true)
//}
//
//func windowIdToPsn(_ wid: CGWindowID) -> ProcessSerialNumber {
//    var elementConnection = UInt32(0)
//    CGSGetWindowOwner(cgsMainConnectionId, wid, &elementConnection)
//    var psn = ProcessSerialNumber()
//    CGSGetConnectionPSN(elementConnection, &psn)
//    return psn
//}
//
//
//// the following functions can be used to handle child-windows
//// see https://developer.apple.com/documentation/appkit/nswindow/1419236-childwindows
//// example of usage:
////   var windowList = [] as CFArray
////   var windowCount = 10 as UInt
////   CGSCopyWindowGroup(cgsMainConnectionId, wid, "movementGroup" as CFString, &windowList, &windowCount)
////   let wins = SLSCopyAssociatedWindows(cgsMainConnectionId, try currentWindows![0].cgWindowId()!)
////   let query = SLSWindowQueryWindows(cgsMainConnectionId, [try currentWindows![0].cgWindowId()!] as CFArray, 1)
////   let iterator = SLSWindowQueryResultCopyWindows(query)
////   while SLSWindowIteratorAdvance(iterator) == .success {
////       let parent_wid = SLSWindowIteratorGetParentID(iterator)
////       let wid = SLSWindowIteratorGetWindowID(iterator)
////       let tags = SLSWindowIteratorGetTags(iterator)
////   }
//
//@_silgen_name("CGSCopyWindowGroup")
//func CGSCopyWindowGroup(_ cid: CGSConnectionID, _ wid: CGWindowID, _ groupType: CFString, _ windowList: inout CFArray, _ windowCount: inout UInt) -> Void
//
//@_silgen_name("SLSCopyAssociatedWindows")
//func SLSCopyAssociatedWindows(_ cid: CGSConnectionID, _ wid: CGWindowID) -> CFArray
//
//@_silgen_name("SLSWindowQueryWindows")
//func SLSWindowQueryWindows(_ cid: CGSConnectionID, _ wids: CFArray, _ windowsCount: UInt) -> CFTypeRef
//
//@_silgen_name("SLSWindowQueryResultCopyWindows")
//func SLSWindowQueryResultCopyWindows(_ query: CFTypeRef) -> CFTypeRef
//
//@_silgen_name("SLSWindowIteratorAdvance")
//func SLSWindowIteratorAdvance(_ iterator: CFTypeRef) -> CGError
//
//@_silgen_name("SLSWindowIteratorGetParentID")
//func SLSWindowIteratorGetParentID(_ iterator: CFTypeRef) -> CGWindowID
//
//@_silgen_name("SLSWindowIteratorGetWindowID")
//func SLSWindowIteratorGetWindowID(_ iterator: CFTypeRef) -> CGWindowID
//
//@_silgen_name("SLSWindowIteratorGetTags")
//func SLSWindowIteratorGetTags(_ iterator: CFTypeRef) -> UInt