// Extracted from INNO-MAKER/usb2can macOS SDK headers.

#pragma once

#import "UsbIO.h"

#define CAN_EFF_FLAG 0x80000000U
#define CAN_RTR_FLAG 0x40000000U
#define CAN_ERR_FLAG 0x20000000U

#define CAN_SFF_MASK 0x000007FFU
#define CAN_EFF_MASK 0x1FFFFFFFU
#define CAN_ERR_MASK 0x1FFFFFFFU
#define CAN_ID_MASK  0x1FFFFFFF

#define CAN_ERR_CRTL 0x00000004U
#define CAN_ERR_BUSOFF 0x00000040U
#define CAN_ERR_RESTARTED 0x00000100U

#define CAN_ERR_CRTL_UNSPEC 0x00
#define CAN_ERR_CRTL_RX_OVERFLOW 0x01
#define CAN_ERR_CRTL_TX_OVERFLOW 0x02
#define CAN_ERR_CRTL_RX_WARNING 0x04
#define CAN_ERR_CRTL_TX_WARNING 0x08
#define CAN_ERR_CRTL_RX_PASSIVE 0x10
#define CAN_ERR_CRTL_TX_PASSIVE 0x20

#define CAN_SFF_ID_BITS 11
#define CAN_EFF_ID_BITS 29

struct innomaker_host_frame {
    uint32_t echo_id;
    uint32_t can_id;
    uint8_t can_dlc;
    uint8_t channel;
    uint8_t flags;
    uint8_t reserved;
    uint8_t data[8];
    uint32_t timestamp_us;
};

struct innomaker_device_mode {
    uint32_t mode;
    uint32_t flags;
};

struct innomaker_device_bittiming {
    uint32_t prop_seg;
    uint32_t phase_seg1;
    uint32_t phase_seg2;
    uint32_t sjw;
    uint32_t brp;
};

struct innomaker_identify_mode {
    uint32_t mode;
};

typedef enum : NSUInteger {
    UsbCanModeNormal,
    UsbCanModeLoopback,
    UsbCanModeListenOnly,
} UsbCanMode;

@interface UsbIO (USBCan)
- (BOOL)UrbResetDevice:(InnoMakerDevice *)device;
- (BOOL)UrbSetupDevice:(InnoMakerDevice *)dev
                  mode:(UsbCanMode)mode
             bittiming:(struct innomaker_device_bittiming)bittiming;
@end
