// Extracted from INNO-MAKER/usb2can macOS SDK headers.

#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#import <unistd.h>

@interface InnoMakerDevice : NSObject {
    IOUSBDeviceInterface245 **InnoMakerDev;
    IOUSBInterfaceInterface245 **InnoMakerIntf;
    UInt8 pipeIn;
    UInt8 pipeOut;
    UInt32 deviceID;
    UInt16 maxPacketSizeIn;
    UInt16 maxPacketSizeOut;
    BOOL _open;
}
@property(nonatomic, assign) IOUSBDeviceInterface245 **InnoMakerDev;
@property(nonatomic, assign) IOUSBInterfaceInterface245 **InnoMakerIntf;
@property(nonatomic, assign) UInt8 pipeIn;
@property(nonatomic, assign) UInt8 pipeOut;
@property(nonatomic, assign) UInt8 controlPipe;
@property(nonatomic, assign) UInt32 deviceID;
@property(nonatomic, assign) UInt16 maxPacketSizeIn;
@property(nonatomic, assign) UInt16 maxPacketSizeOut;
@property BOOL isOpen;
@end

@protocol InnoMakerDeviceDelegate
- (void)addDeviceNotify:(InnoMakerDevice *)device;
- (void)removeDeviceNotify:(InnoMakerDevice *)device;
- (void)readDeviceDataNotify:(InnoMakerDevice *)device
                        data:(Byte *)data
                      length:(NSUInteger)length;
- (void)writeDeviceDataNotify:(InnoMakerDevice *)device
                         data:(Byte *)data
                       length:(NSUInteger)length;
@end

@interface UsbIO : NSObject {
    NSMutableArray *InnoMakerDevices;
    NSThread *monitorThread;
    UInt32 PID;
    UInt32 VID;
}

@property (nonatomic, strong) NSMutableArray *InnoMakerDevices;
@property (nonatomic, weak) NSObject<InnoMakerDeviceDelegate> *delegate;

- (NSString *)getDllVersion;
- (IOReturn)scanInnoMakerDevices;
- (NSUInteger)getInnoMakerDeviceCount;
- (BOOL)openInnoMakerDevice:(InnoMakerDevice *)dev;
- (BOOL)closeInnoMakerDevice:(InnoMakerDevice *)dev;
- (InnoMakerDevice *)getInnoMakerDevice:(UInt8)devIndex;
- (IOReturn)asyncGetInnoMakerDeviceBuf:(InnoMakerDevice *)dev
                             andBuffer:(Byte *)buf
                               andSize:(UInt32)pSize
                            andTimeOut:(UInt32)timeout;
- (IOReturn)asyncSendInnoMakerDeviceBuf:(InnoMakerDevice *)dev
                              andBuffer:(Byte *)buf
                                andSize:(UInt32)pSize
                             andTimeOut:(UInt32)timeout;
- (IOReturn)syncGetInnoMakerDeviceBuf:(InnoMakerDevice *)dev
                            andBuffer:(Byte *)buf
                              andSize:(UInt32)pSize
                           andTimeOut:(UInt32)timeout;
- (IOReturn)syncSendInnoMakerDeviceBuf:(InnoMakerDevice *)dev
                             andBuffer:(Byte *)buf
                               andSize:(UInt32)pSize
                            andTimeOut:(UInt32)timeout;
@end
