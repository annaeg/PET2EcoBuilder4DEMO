#------------------------------------------------------------------------------
# File:         FujiFilm.pm
#
# Description:  Read/write FujiFilm maker notes and RAF images
#
# Revisions:    11/25/2003 - P. Harvey Created
#               11/14/2007 - PH Added abilty to write RAF images
#
# References:   1) http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html
#               2) http://homepage3.nifty.com/kamisaka/makernote/makernote_fuji.htm (2007/09/11)
#               3) Michael Meissner private communication
#               4) Paul Samuelson private communication (S5)
#               5) http://www.cybercom.net/~dcoffin/dcraw/
#               6) http://forums.dpreview.com/forums/readflat.asp?forum=1012&thread=31350384
#                  and http://forum.photome.de/viewtopic.php?f=2&t=353&p=742#p740
#               7) Kai Lappalainen private communication
#               8) http://u88.n24.queensu.ca/exiftool/forum/index.php/topic,5223.0.html
#               9) Iliah Borg private communication
#               JD) Jens Duttke private communication
#------------------------------------------------------------------------------

package Image::ExifTool::FujiFilm;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.44';

sub ProcessFujiDir($$$);
sub ProcessFaceRec($$$);

# the following RAF version numbers have been tested for writing:
my %testedRAF = (
    '0100' => 'E550, E900, F770, S5600, S6000fd, S6500fd, HS10/HS11, HS30, S200EXR, X100, XF1, X-Pro1, X-S1 Ver1.00',
    '0101' => 'X-E1',
    '0102' => 'S100FS, X10 Ver1.02',
    '0103' => 'IS Pro Ver1.03',
    '0104' => 'S5Pro Ver1.04',
    '0106' => 'S5Pro Ver1.06',
    '0111' => 'S5Pro Ver1.11',
    '0114' => 'S9600 Ver1.00',
    '0159' => 'S2Pro Ver1.00',
    '0212' => 'S3Pro Ver2.12',
    '0216' => 'S3Pro Ver2.16', # (NC)
    '0218' => 'S3Pro Ver2.18',
    '0264' => 'F700  Ver2.00',
    '0266' => 'S9500 Ver1.01',
    '0269' => 'S9500 Ver1.02',
    '0271' => 'S3Pro Ver2.71', # UV/IR model?
    '0712' => 'S5000 Ver3.00',
    '0716' => 'S5000 Ver3.00', # (yes, 2 RAF versions with the same firmware version)
);

my %faceCategories = (
    Format => 'int8u',
    PrintConv => { BITMASK => {
        1 => 'Partner',
        2 => 'Family',
        3 => 'Friend',
    }},
);

# FujiFilm MakerNotes tags
%Image::ExifTool::FujiFilm::Main = (
    WRITE_PROC => \&Image::ExifTool::Exif::WriteExif,
    CHECK_PROC => \&Image::ExifTool::Exif::CheckExif,
    WRITABLE => 1,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x0 => {
        Name => 'Version',
        Writable => 'undef',
    },
    0x0010 => { #PH (how does this compare to actual serial number?)
        Name => 'InternalSerialNumber',
        Writable => 'string',
        Notes => q{
            this number is unique, and contains the date of manufacture, but doesn't
            necessarily correspond to the camera body number -- this needs to be checked
        },
        # ie)  "FPX20017035 592D31313034060427796060110384"
        # "FPX 20495643     592D313335310701318AD010110047" (F40fd)
        #                               yymmdd
        PrintConv => q{
            return $val unless $val=~/^(.*)(\d{2})(\d{2})(\d{2})(.{12})$/;
            my $yr = $2 + ($2 < 70 ? 2000 : 1900);
            return "$1 $yr:$3:$4 $5";
        },
        PrintConvInv => '$_=$val; s/ (19|20)(\d{2}):(\d{2}):(\d{2}) /$2$3$4/; $_',
    },
    0x1000 => {
        Name => 'Quality',
        Writable => 'string',
    },
    0x1001 => {
        Name => 'Sharpness',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x01 => 'Soft',
            0x02 => 'Soft2',
            0x03 => 'Normal',
            0x04 => 'Hard',
            0x05 => 'Hard2',
            0x82 => 'Medium Soft', #2
            0x84 => 'Medium Hard', #2
            0x8000 => 'Film Simulation', #2
            0xffff => 'n/a', #2
        },
    },
    0x1002 => {
        Name => 'WhiteBalance',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x0   => 'Auto',
            0x100 => 'Daylight',
            0x200 => 'Cloudy',
            0x300 => 'Daylight Fluorescent',
            0x301 => 'Day White Fluorescent',
            0x302 => 'White Fluorescent',
            0x303 => 'Warm White Fluorescent', #2/PH (S5)
            0x304 => 'Living Room Warm White Fluorescent', #2/PH (S5)
            0x400 => 'Incandescent',
            0x500 => 'Flash', #4
            0xf00 => 'Custom',
            0xf01 => 'Custom2', #2
            0xf02 => 'Custom3', #2
            0xf03 => 'Custom4', #2
            0xf04 => 'Custom5', #2
            # 0xfe0 => 'Gray Point?', #2
            0xff0 => 'Kelvin', #4
        },
    },
    0x1003 => {
        Name => 'Saturation',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x0   => 'Normal', # # ("Color 0", ref 8)
            0x080 => 'Medium High', #2 ("Color +1", ref 8)
            0x100 => 'High', # ("Color +2", ref 8)
            0x180 => 'Medium Low', #2 ("Color -1", ref 8)
            0x200 => 'Low',
            0x300 => 'None (B&W)', #2
            0x301 => 'B&W Red Filter', #PH/8
            0x302 => 'B&W Yellow Filter', #PH (X100)
            0x303 => 'B&W Green Filter', #PH/8
            0x310 => 'B&W Sepia', #PH (X100)
            0x400 => 'Low 2', #8 ("Color -2")
            0x8000 => 'Film Simulation', #2
        },
    },
    0x1004 => {
        Name => 'Contrast',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x0   => 'Normal',
            0x080 => 'Medium High', #2
            0x100 => 'High',
            0x180 => 'Medium Low', #2
            0x200 => 'Low',
            0x8000 => 'Film Simulation', #2
        },
    },
    0x1005 => { #4
        Name => 'ColorTemperature',
        Writable => 'int16u',
    },
    0x1006 => { #JD
        Name => 'Contrast',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x0   => 'Normal',
            0x100 => 'High',
            0x300 => 'Low',
        },
    },
    0x100a => { #2
        Name => 'WhiteBalanceFineTune',
        Writable => 'int32s',
        Count => 2,
        PrintConv => 'sprintf("Red %+d, Blue %+d", split(" ", $val))',
        PrintConvInv => 'my @v=($val=~/-?\d+/g);"@v"',
    },
    0x100b => { #2
        Name => 'NoiseReduction',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x40 => 'Low',
            0x80 => 'Normal',
            0x100 => 'n/a', #PH (NC) (all X100 samples)
        },
    },
    0x100e => { #PH (X100)
        Name => 'HighISONoiseReduction',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x000 => 'Normal', # ("NR 0, ref 8)
            0x100 => 'Strong', # ("NR+2, ref 8)
            0x180 => 'Medium Strong', #8 ("NR+1")
            0x200 => 'Weak', # ("NR-2, ref 8)
            0x280 => 'Medium Weak', #8 ("NR-1")
        },
    },
    0x1010 => {
        Name => 'FujiFlashMode',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'On',
            2 => 'Off',
            3 => 'Red-eye reduction',
            4 => 'External', #JD
        },
    },
    0x1011 => {
        Name => 'FlashExposureComp', #JD
        Writable => 'rational64s',
    },
    0x1020 => {
        Name => 'Macro',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    0x1021 => {
        Name => 'FocusMode',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'Manual',
        },
    },
    0x1022 => { #8
        Name => 'AFPointSet',
        Writable => 'int16u',
        Notes => '"No" for manual and AF-multi focus modes',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    0x1023 => { #2
        Name => 'FocusPixel',
        Writable => 'int16u',
        Count => 2,
    },
    0x1030 => {
        Name => 'SlowSync',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
        },
    },
    0x1031 => {
        Name => 'PictureMode',
        Flags => 'PrintHex',
        Writable => 'int16u',
        PrintConv => {
            0x0 => 'Auto',
            0x1 => 'Portrait',
            0x2 => 'Landscape',
            0x3 => 'Macro', #JD
            0x4 => 'Sports',
            0x5 => 'Night Scene',
            0x6 => 'Program AE',
            0x7 => 'Natural Light', #3
            0x8 => 'Anti-blur', #3
            0x9 => 'Beach & Snow', #JD
            0xa => 'Sunset', #3
            0xb => 'Museum', #3
            0xc => 'Party', #3
            0xd => 'Flower', #3
            0xe => 'Text', #3
            0xf => 'Natural Light & Flash', #3
            0x10 => 'Beach', #3
            0x11 => 'Snow', #3
            0x12 => 'Fireworks', #3
            0x13 => 'Underwater', #3
            0x14 => 'Portrait with Skin Correction', #7
            0x16 => 'Panorama', #PH (X100)
            0x17 => 'Night (tripod)', #7
            0x18 => 'Pro Low-light', #7
            0x19 => 'Pro Focus', #7
            0x1a => 'Portrait 2', #PH (NC, T500, maybe "Smile & Shoot"?)
            0x1b => 'Dog Face Detection', #7
            0x1c => 'Cat Face Detection', #7
            0x40 => 'Advanced Filter',
            0x100 => 'Aperture-priority AE',
            0x200 => 'Shutter speed priority AE',
            0x300 => 'Manual',
        },
    },
    0x1032 => { #8
        Name => 'ExposureCount',
        Writable => 'int16u',
        Notes => 'number of exposures used for this image',
    },
    0x1033 => { #6
        Name => 'EXRAuto',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Auto',
            1 => 'Manual',
        },
    },
    0x1034 => { #6
        Name => 'EXRMode',
        Writable => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x100 => 'HR (High Resolution)',
            0x200 => 'SN (Signal to Noise priority)',
            0x300 => 'DR (Dynamic Range priority)',
        },
    },
    0x1040 => { #8
        Name => 'ShadowTone',
        Writable => 'int32s',
        PrintConv => {
            -32 => 'Hard',
            -16 => 'Medium-hard',
            0 => 'Normal',
            16 => 'Medium-soft',
            32 => 'Soft',
        },
    },
    0x1041 => { #8
        Name => 'HighlightTone',
        Writable => 'int32s',
        PrintConv => {
            -32 => 'Hard',
            -16 => 'Medium-hard',
            0 => 'Normal',
            16 => 'Medium-soft',
            32 => 'Soft',
        },
    },
    0x1100 => {
        Name => 'AutoBracketing',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Off',
            1 => 'On',
            2 => 'No flash & flash', #3
        },
    },
    0x1101 => {
        Name => 'SequenceNumber',
        Writable => 'int16u',
    },
    # (0x1150-0x1152 exist only for Pro Low-light and Pro Focus PictureModes)
    # 0x1150 - Pro Low-light - val=1; Pro Focus - val=2 (ref 7)
    # 0x1151 - Pro Low-light - val=4 (number of pictures taken?); Pro Focus - val=2,3 (ref 7)
    # 0x1152 - Pro Low-light - val=1,3,4 (stacked pictures used?); Pro Focus - val=1,2 (ref 7)
    0x1210 => { #2
        Name => 'ColorMode',
        Writable => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x00 => 'Standard',
            0x10 => 'Chrome',
            0x30 => 'B & W',
        },
    },
    0x1300 => {
        Name => 'BlurWarning',
        Writable => 'int16u',
        PrintConv => {
            0 => 'None',
            1 => 'Blur Warning',
        },
    },
    0x1301 => {
        Name => 'FocusWarning',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Good',
            1 => 'Out of focus',
        },
    },
    0x1302 => {
        Name => 'ExposureWarning',
        Writable => 'int16u',
        PrintConv => {
            0 => 'Good',
            1 => 'Bad exposure',
        },
    },
    0x1304 => { #PH
        Name => 'GEImageSize',
        Condition => '$$self{Make} =~ /^GENERAL IMAGING/',
        Format => 'string',
        Notes => 'GE models only',
    },
    0x1400 => { #2
        Name => 'DynamicRange',
        Writable => 'int16u',
        PrintConv => {
            1 => 'Standard',
            3 => 'Wide',
            # the S5Pro has 100%(STD),130%,170%,230%(W1),300%,400%(W2) - PH
        },
    },
    0x1401 => { #2 (this doesn't seem to work for the X100 - PH)
        Name => 'FilmMode',
        Writable => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x000 => 'F0/Standard (Provia)',
            0x100 => 'F1/Studio Portrait',
            0x110 => 'F1a/Studio Portrait Enhanced Saturation',
            0x120 => 'F1b/Studio Portrait Smooth Skin Tone (Astia)',
            0x130 => 'F1c/Studio Portrait Increased Sharpness',
            0x200 => 'F2/Fujichrome (Velvia)',
            0x300 => 'F3/Studio Portrait Ex',
            0x400 => 'F4/Velvia',
            0x500 => 'Pro Neg. Std', #PH (X-Pro1)
            0x501 => 'Pro Neg. Hi', #PH (X-Pro1)
        },
    },
    0x1402 => { #2
        Name => 'DynamicRangeSetting',
        Writable => 'int16u',
        PrintHex => 1,
        PrintConv => {
            0x000 => 'Auto (100-400%)',
            0x001 => 'Manual', #(ref http://forum.photome.de/viewtopic.php?f=2&t=353)
            0x100 => 'Standard (100%)',
            0x200 => 'Wide1 (230%)',
            0x201 => 'Wide2 (400%)',
            0x8000 => 'Film Simulation',
        },
    },
    0x1403 => { #2 (only valid for manual DR, ref 6)
        Name => 'DevelopmentDynamicRange',
        Writable => 'int16u',
    },
    0x1404 => { #2
        Name => 'MinFocalLength',
        Writable => 'rational64s',
    },
    0x1405 => { #2
        Name => 'MaxFocalLength',
        Writable => 'rational64s',
    },
    0x1406 => { #2
        Name => 'MaxApertureAtMinFocal',
        Writable => 'rational64s',
    },
    0x1407 => { #2
        Name => 'MaxApertureAtMaxFocal',
        Writable => 'rational64s',
    },
    # 0x1408 - values: '0100', 'S100', 'VQ10'
    # 0x1409 - values: same as 0x1408
    # 0x140a - values: 0, 1, 3, 5, 7
    0x140b => { #6
        Name => 'AutoDynamicRange',
        Writable => 'int16u',
        PrintConv => '"$val%"',
        PrintConvInv => '$val=~s/\s*\%$//; $val',
    },
    0x1422 => { #8
        Name => 'ImageStabilization',
        Writable => 'int16u',
        Count => 3,
        PrintConv => [{
            0 => 'None',
            1 => 'Optical', #PH
            2 => 'Sensor-shift', #PH
            512 => 'Digital', #PH
        },{
            0 => 'Off',
            1 => 'On (mode 1, continuous)',
            2 => 'On (mode 2, shooting only)',
        }],
    },
    0x1436 => { #8
        Name => 'ImageGeneration',
        Format => 'int16u',
        PrintConv => {
            0 => 'Original Image',
            1 => 'Re-developed from RAW',
        },
    },
    0x3820 => { #PH (HS20EXR MOV)
        Name => 'FrameRate',
        Writable => 'int16u',
        Groups => { 2 => 'Video' },
    },
    0x3821 => { #PH (HS20EXR MOV)
        Name => 'FrameWidth',
        Writable => 'int16u',
        Groups => { 2 => 'Video' },
    },
    0x3822 => { #PH (HS20EXR MOV)
        Name => 'FrameHeight',
        Writable => 'int16u',
        Groups => { 2 => 'Video' },
    },
    0x4100 => { #PH
        Name => 'FacesDetected',
        Writable => 'int16u',
    },
    0x4103 => { #PH
        Name => 'FacePositions',
        Writable => 'int16u',
        Count => -1,
        Notes => q{
            left, top, right and bottom coordinates in full-sized image for each face
            detected
        },
    },
    # 0x4101-0x4105 - exist only if face detection active
    # 0x4104 - also related to face detection (same number of entries as FacePositions)
    # 0x4200 - same as 0x4100?
    # 0x4203 - same as 0x4103
    # 0x4204 - same as 0x4104
    0x4282 => { #PH
        Name => 'FaceRecInfo',
        SubDirectory => { TagTable => 'Image::ExifTool::FujiFilm::FaceRecInfo' },
    },
    0x8000 => { #2
        Name => 'FileSource',
        Writable => 'string',
    },
    0x8002 => { #2
        Name => 'OrderNumber',
        Writable => 'int32u',
    },
    0x8003 => { #2
        Name => 'FrameNumber',
        Writable => 'int16u',
    },
    0xb211 => { #PH
        Name => 'Parallax',
        # (value set in camera is -0.5 times this value in MPImage2... why?)
        Writable => 'rational64s',
        Notes => 'only found in MPImage2 of .MPO images',
    },
    # 0xb212 - also found in MPIMage2 images - PH
);

# Face recognition information from FinePix F550EXR (ref PH)
%Image::ExifTool::FujiFilm::FaceRecInfo = (
    PROCESS_PROC => \&ProcessFaceRec,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Image' },
    VARS => { NO_ID => 1 },
    NOTES => 'Face recognition information.',
    Face1Name => { },
    Face2Name => { },
    Face3Name => { },
    Face4Name => { },
    Face5Name => { },
    Face6Name => { },
    Face7Name => { },
    Face8Name => { },
    Face1Category => { %faceCategories },
    Face2Category => { %faceCategories },
    Face3Category => { %faceCategories },
    Face4Category => { %faceCategories },
    Face5Category => { %faceCategories },
    Face6Category => { %faceCategories },
    Face7Category => { %faceCategories },
    Face8Category => { %faceCategories },
    Face1Birthday => { },
    Face2Birthday => { },
    Face3Birthday => { },
    Face4Birthday => { },
    Face5Birthday => { },
    Face6Birthday => { },
    Face7Birthday => { },
    Face8Birthday => { },
);

# tags in RAF images (ref 5)
%Image::ExifTool::FujiFilm::RAF = (
    PROCESS_PROC => \&ProcessFujiDir,
    GROUPS => { 0 => 'RAF', 1 => 'RAF', 2 => 'Image' },
    PRIORITY => 0, # so the first RAF directory takes precedence
    NOTES => q{
        FujiFilm RAF images contain meta information stored in a proprietary
        FujiFilm RAF format, as well as EXIF information stored inside an embedded
        JPEG preview image.  The table below lists tags currently decoded from the
        RAF-format information.
    },
    0x100 => {
        Name => 'RawImageFullSize',
        Format => 'int16u',
        Groups => { 1 => 'RAF2' }, # (so RAF2 shows up in family 1 list)
        Count => 2,
        Notes => 'including borders',
        ValueConv => 'my @v=reverse split(" ",$val);"@v"',
        PrintConv => '$val=~tr/ /x/; $val',
    },
    0x121 => [
        {
            Name => 'RawImageSize',
            Condition => '$$self{Model} eq "FinePixS2Pro"',
            Format => 'int16u',
            Count => 2,
            ValueConv => q{
                my @v=split(" ",$val);
                $v[0]*=2, $v[1]/=2;
                return "@v";
            },
            PrintConv => '$val=~tr/ /x/; $val',
        },
        {
            Name => 'RawImageSize',
            Format => 'int16u',
            Count => 2,
            # values are height then width, adjusted for the layout
            ValueConv => q{
                my @v=reverse split(" ",$val);
                $$self{FujiLayout} and $v[0]/=2, $v[1]*=2;
                return "@v";
            },
            PrintConv => '$val=~tr/ /x/; $val',
        },
    ],
    0x130 => {
        Name => 'FujiLayout',
        Format => 'int8u',
        RawConv => q{
            my ($v) = split ' ', $val;
            $$self{FujiLayout} = $v & 0x80 ? 1 : 0;
            return $val;
        },
    },
    0x2ff0 => {
        Name => 'WB_GRGBLevels',
        Format => 'int16u',
        Count => 4,
    },
    0xc000 => {
        Name => 'RAFData',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FujiFilm::RAFData',
            ByteOrder => 'Little-endian',
        }
    },
);

%Image::ExifTool::FujiFilm::RAFData = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    # (FujiFilm image dimensions are REALLY confusing)
    0 => {
        Name => 'RawImageWidth',
        Format => 'int32u',
        RawConv => '$val < 10000 ? $$self{FujiWidth} = $val : undef', #5
        ValueConv => '$$self{FujiLayout} ? ($val / 2) : $val',
    },
    4 => [
        {
            Name => 'RawImageWidth',
            Condition => 'not $$self{FujiWidth}',
            Format => 'int32u',
            ValueConv => '$$self{FujiLayout} ? ($val / 2) : $val',
        },
        {
            Name => 'RawImageHeight',
            Format => 'int32u',
            ValueConv => '$$self{FujiLayout} ? ($val * 2) : $val',
        },
    ],
    8 => {
        Name => 'RawImageHeight',
        Condition => 'not $$self{FujiWidth}',
        Format => 'int32u',
        ValueConv => '$$self{FujiLayout} ? ($val * 2) : $val',
    },
);

# TIFF IFD-format information stored in FujiFilm RAF images (ref 5)
%Image::ExifTool::FujiFilm::IFD = (
    PROCESS_PROC => \&Image::ExifTool::Exif::ProcessExif,
    GROUPS => { 0 => 'RAF', 1 => 'FujiIFD', 2 => 'Image' },
    NOTES => 'Tags found in the FujiIFD information of RAF images from some models.',
    0xf000 => {
        Name => 'FujiIFD',
        Groups => { 1 => 'FujiIFD' },
        Flags => 'SubIFD',
        SubDirectory => {
            TagTable => 'Image::ExifTool::FujiFilm::IFD',
            DirName => 'FujiSubIFD',
            Start => '$val',
        },
    },
    0xf001 => 'RawImageFullWidth',
    0xf002 => 'RawImageFullHeight',
    0xf003 => 'BitsPerSample',
    # 0xf004 - values: 4
    # 0xf005 - values: 1374, 1668
    # 0xf006 - some sort of flag indicating packed format?
    0xf007 => {
        Name => 'StripOffsets',
        IsOffset => 1,
        OffsetPair => 0xf008,  # point to associated byte counts
    },
    0xf008 => {
        Name => 'StripByteCounts',
        OffsetPair => 0xf007,  # point to associated offsets
    },
    # 0xf009 - values: 0, 3
    # 0xf00a-0xf00b ?
    0xf00c => 'WB_GRBLevelsStandard', #9 (GRBXGRBX; X=17 is standard illuminant A, X=21 is D65)
    0xf00d => 'WB_GRBLevelsDaylight', #9
    0xf00e => 'WB_GRBLevels',
    # 0xf00f ?
);

# information found in FFMV atom of MOV videos
%Image::ExifTool::FujiFilm::FFMV = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => 'Information found in the FFMV atom of MOV videos.',
    0 => {
        Name => 'MovieStreamName',
        Format => 'string[34]',
    },
);

# tags in FujiFilm QuickTime videos (ref PH)
# (similar information in Kodak,Minolta,Nikon,Olympus,Pentax and Sanyo videos)
%Image::ExifTool::FujiFilm::MOV = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    FIRST_ENTRY => 0,
    NOTES => 'This information is found in MOV videos from some FujiFilm cameras.',
    0x00 => {
        Name => 'Make',
        Format => 'string[24]',
    },
    0x18 => {
        Name => 'Model',
        Description => 'Camera Model Name',
        Format => 'string[16]',
    },
    0x2e => { # (NC)
        Name => 'ExposureTime',
        Format => 'int32u',
        ValueConv => '$val ? 1 / $val : 0',
        PrintConv => 'Image::ExifTool::Exif::PrintExposureTime($val)',
    },
    0x32 => {
        Name => 'FNumber',
        Format => 'rational64u',
        PrintConv => 'sprintf("%.1f",$val)',
    },
    0x3a => { # (NC)
        Name => 'ExposureCompensation',
        Format => 'rational64s',
        PrintConv => '$val ? sprintf("%+.1f", $val) : 0',
    },
);

#------------------------------------------------------------------------------
# decode information from FujiFilm face recognition information
# Inputs: 0) ExifTool object reference, 1) dirInfo reference, 2) tag table ref
# Returns: 1
sub ProcessFaceRec($$$)
{
    my ($et, $dirInfo, $tagTablePtr) = @_;
    my $dataPt = $$dirInfo{DataPt};
    my $dataPos = $$dirInfo{DataPos} + ($$dirInfo{Base} || 0);
    my $dirStart = $$dirInfo{DirStart};
    my $dirLen = $$dirInfo{DirLen};
    my $pos = $dirStart;
    my $end = $dirStart + $dirLen;
    my ($i, $n, $p, $val);
    $et->VerboseDir('FaceRecInfo');
    for ($i=1; ; ++$i) {
        last if $pos + 8 > $end;
        my $off = Get32u($dataPt, $pos) + $dirStart;
        my $len = Get32u($dataPt, $pos + 4);
        last if $len==0 or $off>$end or $off+$len>$end or $len < 62;
        # values observed for each offset (always zero if not listed):
        # 0=5; 3=1; 4=4; 6=1; 10-13=numbers(constant for a given registered face)
        # 15=16; 16=3; 18=1; 22=nameLen; 26=1; 27=16; 28=7; 30-33=nameLen(int32u)
        # 34-37=nameOffset(int32u); 38=32; 39=16; 40=4; 42=1; 46=0,2,4,8(category)
        # 50=33; 51=16; 52=7; 54-57=dateLen(int32u); 58-61=dateOffset(int32u)
        $n = Get32u($dataPt, $off + 30);
        $p = Get32u($dataPt, $off + 34) + $dirStart;
        last if $p < $dirStart or $p + $n > $end;
        $val = substr($$dataPt, $p, $n);
        $et->HandleTag($tagTablePtr, "Face${i}Name", $val,
            DataPt  => $dataPt,
            DataPos => $dataPos,
            Start   => $p,
            Size    => $n,
        );
        $n = Get32u($dataPt, $off + 54);
        $p = Get32u($dataPt, $off + 58) + $dirStart;
        last if $p < $dirStart or $p + $n > $end;
        $val = substr($$dataPt, $p, $n);
        $val =~ s/(\d{4})(\d{2})(\d{2})/$1:$2:$2/;
        $et->HandleTag($tagTablePtr, "Face${i}Birthday", $val,
            DataPt  => $dataPt,
            DataPos => $dataPos,
            Start   => $p,
            Size    => $n,
        );
        $et->HandleTag($tagTablePtr, "Face${i}Category", undef,
            DataPt  => $dataPt,
            DataPos => $dataPos,
            Start   => $off + 46,
            Size    => 1,
        );
        $pos += 8;
    }
    return 1;
}

#------------------------------------------------------------------------------
# get information from FujiFilm RAF directory
# Inputs: 0) ExifTool object reference, 1) dirInfo reference, 2) tag table ref
# Returns: 1 if this was a valid FujiFilm directory
sub ProcessFujiDir($$$)
{
    my ($et, $dirInfo, $tagTablePtr) = @_;
    my $raf = $$dirInfo{RAF};
    my $offset = $$dirInfo{DirStart};
    $raf->Seek($offset, 0) or return 0;
    my ($buff, $index);
    $raf->Read($buff, 4) or return 0;
    my $entries = unpack 'N', $buff;
    $entries < 256 or return 0;
    $et->Options('Verbose') and $et->VerboseDir('Fuji', $entries);
    SetByteOrder('MM');
    my $pos = $offset + 4;
    for ($index=0; $index<$entries; ++$index) {
        $raf->Read($buff,4) or return 0;
        $pos += 4;
        my ($tag, $len) = unpack 'nn', $buff;
        my ($val, $vbuf);
        $raf->Read($vbuf, $len) or return 0;
        my $tagInfo = $et->GetTagInfo($tagTablePtr, $tag);
        if ($tagInfo and $$tagInfo{Format}) {
            $val = ReadValue(\$vbuf, 0, $$tagInfo{Format}, $$tagInfo{Count}, $len);
            next unless defined $val;
        } elsif ($len == 4) {
            # interpret unknown 4-byte values as int32u
            $val = Get32u(\$vbuf, 0);
        } else {
            # treat other unknown values as binary data
            $val = \$vbuf;
        }
        $et->HandleTag($tagTablePtr, $tag, $val,
            Index   => $index,
            DataPt  => \$vbuf,
            DataPos => $pos,
            Size    => $len,
            TagInfo => $tagInfo,
        );
        $pos += $len;
    }
    return 1;
}

#------------------------------------------------------------------------------
# write information to FujiFilm RAW file (RAF)
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 on success, 0 if this wasn't a valid RAF file, or -1 on write error
sub WriteRAF($$)
{
    my ($et, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my ($hdr, $jpeg, $outJpeg, $offset, $err, $buff);

    $raf->Read($hdr,0x94) == 0x94  or return 0;
    $hdr =~ /^FUJIFILM/            or return 0;
    my $ver = substr($hdr, 0x3c, 4);
    $ver =~ /^\d{4}$/              or return 0;

    # get the position and size of embedded JPEG
    my ($jpos, $jlen) = unpack('x84NN', $hdr);
    # check to be sure the JPEG starts in the expected location
    if ($jpos > 0x94 or $jpos < 0x68 or $jpos & 0x03) {
        $et->Error("Unsupported or corrupted RAF image (version $ver)");
        return 1;
    }
    # check to make sure this version of RAF has been tested
    unless ($testedRAF{$ver}) {
        $et->Warn("RAF version $ver not yet tested", 1);
    }
    # read the embedded JPEG
    unless ($raf->Seek($jpos, 0) and $raf->Read($jpeg, $jlen) == $jlen) {
        $et->Error('Error reading RAF meta information');
        return 1;
    }
    # use same write directories as JPEG
    $et->InitWriteDirs('JPEG');
    # rewrite the embedded JPEG in memory
    my %jpegInfo = (
        Parent  => 'RAF',
        RAF     => new File::RandomAccess(\$jpeg),
        OutFile => \$outJpeg,
    );
    $$et{FILE_TYPE} = 'JPEG';
    my $success = $et->WriteJPEG(\%jpegInfo);
    $$et{FILE_TYPE} = 'RAF';
    unless ($success and $outJpeg) {
        $et->Error("Invalid RAF format");
        return 1;
    }
    return -1 if $success < 0;

    # rewrite the RAF image
    SetByteOrder('MM');
    my $jpegLen = length $outJpeg;
    # pad JPEG to an even 4 bytes (ALWAYS use padding as Fuji does)
    my $pad = "\0" x (4 - ($jpegLen % 4));
    # update JPEG size in header (size without padding)
    Set32u(length($outJpeg), \$hdr, 0x58);
    # get pointer to start of the next RAF block
    my $nextPtr = Get32u(\$hdr, 0x5c);
    # determine the length of padding at the end of the original JPEG
    my $oldPadLen = $nextPtr - ($jpos + $jlen);
    if ($oldPadLen) {
        if ($oldPadLen > 1000000 or $oldPadLen < 0 or
            not $raf->Seek($jpos+$jlen, 0) or
            $raf->Read($buff, $oldPadLen) != $oldPadLen)
        {
            $et->Error('Bad RAF pointer at 0x5c');
            return 1;
        }
        # make sure padding is only zero bytes (can be >100k for HS10)
        # (have seen non-null padding in X-Pro1)
        if ($buff =~ /[^\0]/) {
            return 1 if $et->Error('Non-null bytes found in padding', 2);
        }
    }
    # calculate offset difference due to change in JPEG size
    my $ptrDiff = length($outJpeg) + length($pad) - ($jlen + $oldPadLen);
    # update necessary pointers in header
    foreach $offset (0x5c, 0x64, 0x78, 0x80) {
        last if $offset >= $jpos;   # some versions have a short header
        my $oldPtr = Get32u(\$hdr, $offset);
        next unless $oldPtr;        # don't update if pointer is zero
        Set32u($oldPtr + $ptrDiff, \$hdr, $offset);
    }
    # write the new header
    my $outfile = $$dirInfo{OutFile};
    Write($outfile, substr($hdr, 0, $jpos)) or $err = 1;
    # write the updated JPEG plus padding
    Write($outfile, $outJpeg, $pad) or $err = 1;
    # copy over the rest of the RAF image
    unless ($raf->Seek($nextPtr, 0)) {
        $et->Error('Error reading RAF image');
        return 1;
    }
    while ($raf->Read($buff, 65536)) {
        Write($outfile, $buff) or $err = 1, last;
    }
    return $err ? -1 : 1;
}

#------------------------------------------------------------------------------
# get information from FujiFilm RAW file (RAF)
# Inputs: 0) ExifTool object reference, 1) dirInfo reference
# Returns: 1 if this was a valid RAF file
sub ProcessRAF($$)
{
    my ($et, $dirInfo) = @_;
    my ($buff, $jpeg, $warn, $offset);

    my $raf = $$dirInfo{RAF};
    $raf->Read($buff,0x5c) == 0x5c    or return 0;
    $buff =~ /^FUJIFILM/              or return 0;
    my ($jpos, $jlen) = unpack('x84NN', $buff);
    $jpos & 0x8000                   and return 0;
    $raf->Seek($jpos, 0)              or return 0;
    $raf->Read($jpeg, $jlen) == $jlen or return 0;

    $et->SetFileType();
    $et->FoundTag('RAFVersion', substr($buff, 0x3c, 4));

    # extract information from embedded JPEG
    my %dirInfo = (
        Parent => 'RAF',
        RAF    => new File::RandomAccess(\$jpeg),
    );
    $$et{BASE} += $jpos;
    my $rtnVal = $et->ProcessJPEG(\%dirInfo);
    $$et{BASE} -= $jpos;
    $et->FoundTag('PreviewImage', \$jpeg) if $rtnVal;

    # extract information from Fuji RAF and TIFF directories
    my ($rafNum, $ifdNum) = ('','');
    foreach $offset (0x5c, 0x64, 0x78, 0x80) {
        last if $offset >= $jpos;
        unless ($raf->Seek($offset, 0) and $raf->Read($buff, 4)) {
            $warn = 1;
            last;
        }
        my $start = unpack('N',$buff);
        next unless $start;
        if ($offset == 0x64 or $offset == 0x80) {
            # parse FujiIFD directory
            %dirInfo = (
                RAF  => $raf,
                Base => $start,
            );
            $$et{SET_GROUP1} = "FujiIFD$ifdNum";
            my $tagTablePtr = GetTagTable('Image::ExifTool::FujiFilm::IFD');
            # this is TIFF-format data only for some models, so no warning if it fails
            $et->ProcessTIFF(\%dirInfo, $tagTablePtr, \&Image::ExifTool::ProcessTIFF);
            delete $$et{SET_GROUP1};
            $ifdNum = ($ifdNum || 1) + 1;
        } else {
            # parse RAF directory
            %dirInfo = (
                RAF      => $raf,
                DirStart => $start,
            );
            $$et{SET_GROUP1} = "RAF$rafNum";
            my $tagTablePtr = GetTagTable('Image::ExifTool::FujiFilm::RAF');
            $et->ProcessDirectory(\%dirInfo, $tagTablePtr) or $warn = 1;
            delete $$et{SET_GROUP1};
            $rafNum = ($rafNum || 1) + 1;
        }
    }
    $warn and $et->Warn('Possibly corrupt RAF information');

    return $rtnVal;
}

1; # end

__END__

=head1 NAME

Image::ExifTool::FujiFilm - Read/write FujiFilm maker notes and RAF images

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
FujiFilm maker notes in EXIF information, and to read/write FujiFilm RAW
(RAF) images.

=head1 AUTHOR

Copyright 2003-2014, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://park2.wakwak.com/~tsuruzoh/Computer/Digicams/exif-e.html>

=item L<http://homepage3.nifty.com/kamisaka/makernote/makernote_fuji.htm>

=item L<http://www.cybercom.net/~dcoffin/dcraw/>

=item (...plus testing with my own FinePix 2400 Zoom)

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Michael Meissner, Paul Samuelson and Jens Duttke for help decoding
some FujiFilm information.

=head1 SEE ALSO

L<Image::ExifTool::TagNames/FujiFilm Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut
