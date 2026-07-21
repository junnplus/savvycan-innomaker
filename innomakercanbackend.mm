#include "innomakercanbackend.h"

#include <QMetaObject>
#include <QRegularExpression>
#include <QVector>

QT_BEGIN_NAMESPACE

constexpr quint32 kListenOnlyFlag = 0x00000001;
constexpr quint32 kInvalidEchoId = 0xFFFFFFFFU;
constexpr quint32 kReadTimeoutMs = 100;

namespace {

QString hexString(quint32 value)
{
    return QString::number(value, 16).toUpper();
}

} // namespace

QCanBusDeviceInfo InnoMakerCanBackend::createDeviceInfoCompat(const QString &name,
                                                              const QString &serialNumber,
                                                              const QString &description,
                                                              int channel,
                                                              bool isVirtual,
                                                              bool isFlexibleDataRateCapable)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    return createDeviceInfo(pluginKey(),
                            name,
                            serialNumber,
                            description,
                            QString(),
                            channel,
                            isVirtual,
                            isFlexibleDataRateCapable);
#else
    return createDeviceInfo(name,
                            serialNumber,
                            description,
                            channel,
                            isVirtual,
                            isFlexibleDataRateCapable);
#endif
}

QCanBusDeviceInfo InnoMakerCanBackend::createDeviceInfoCompat(const QString &name,
                                                              bool isVirtual,
                                                              bool isFlexibleDataRateCapable)
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    return createDeviceInfo(pluginKey(), name, isVirtual, isFlexibleDataRateCapable);
#else
    return createDeviceInfo(name, isVirtual, isFlexibleDataRateCapable);
#endif
}

InnoMakerCanBackend::InnoMakerCanBackend(const QString &interfaceName, QObject *parent)
    : QCanBusDevice(parent)
    , m_interfaceName(interfaceName)
    , m_deviceIndex(parseInterfaceIndex(interfaceName))
{
    QCanBusDevice::setConfigurationParameter(QCanBusDevice::LoopbackKey, false);
    QCanBusDevice::setConfigurationParameter(QCanBusDevice::ReceiveOwnKey, false);
    QCanBusDevice::setConfigurationParameter(QCanBusDevice::CanFdKey, false);
    QCanBusDevice::setConfigurationParameter(QCanBusDevice::UserKey, 0);
}

InnoMakerCanBackend::~InnoMakerCanBackend()
{
    close();
}

QList<QCanBusDeviceInfo> InnoMakerCanBackend::interfaces(QString *errorMessage)
{
    @autoreleasepool {
        UsbIO *usbIo = [[UsbIO alloc] init];
        if ([usbIo scanInnoMakerDevices] != kIOReturnSuccess) {
            if (errorMessage)
                *errorMessage = QStringLiteral("Failed to enumerate InnoMaker USB2CAN devices.");
            return {};
        }

        QList<QCanBusDeviceInfo> result;
        const NSUInteger count = [usbIo getInnoMakerDeviceCount];
        result.reserve(static_cast<qsizetype>(count));
        for (NSUInteger i = 0; i < count; ++i) {
            InnoMakerDevice *device = [usbIo getInnoMakerDevice:static_cast<UInt8>(i)];
            result.append(createDeviceInfoCompat(interfaceNameForIndex(static_cast<int>(i)),
                                                 deviceSerial(device),
                                                 deviceDescription(),
                                                 static_cast<int>(i),
                                                 false,
                                                 false));
        }
        return result;
    }
}

QCanBusDeviceInfo InnoMakerCanBackend::interfaceInfo(int deviceIndex, QString *errorMessage)
{
    const auto devices = interfaces(errorMessage);
    if (deviceIndex < 0 || deviceIndex >= devices.size())
        return createDeviceInfoCompat(interfaceNameForIndex(deviceIndex), false, false);
    return devices.at(deviceIndex);
}

bool InnoMakerCanBackend::writeFrame(const QCanBusFrame &frame)
{
    if (state() != ConnectedState || !m_usbIo || !m_device) {
        reportError(tr("Device is not connected."), QCanBusDevice::OperationError);
        return false;
    }

    if (!frame.isValid()) {
        reportError(tr("Cannot write invalid CAN frame."), QCanBusDevice::WriteError);
        return false;
    }

    if (frame.hasFlexibleDataRateFormat() || frame.payload().size() > 8) {
        reportError(tr("InnoMaker macOS backend only supports classic CAN frames."),
                    QCanBusDevice::WriteError);
        return false;
    }

    if (frame.frameType() == QCanBusFrame::ErrorFrame) {
        reportError(tr("Sending CAN error frames is not supported."), QCanBusDevice::WriteError);
        return false;
    }

    struct innomaker_host_frame rawFrame = {};
    rawFrame.echo_id = m_nextEchoId.fetch_add(1, std::memory_order_relaxed);
    rawFrame.can_id = frame.frameId() & CAN_EFF_MASK;
    rawFrame.can_dlc = static_cast<uint8_t>(frame.payload().size());
    rawFrame.channel = 0;

    if (frame.hasExtendedFrameFormat())
        rawFrame.can_id |= CAN_EFF_FLAG;
    if (frame.frameType() == QCanBusFrame::RemoteRequestFrame)
        rawFrame.can_id |= CAN_RTR_FLAG;

    const QByteArray payload = frame.payload();
    if (!payload.isEmpty())
        memcpy(rawFrame.data, payload.constData(), static_cast<size_t>(payload.size()));

    const IOReturn result = [m_usbIo syncSendInnoMakerDeviceBuf:m_device
                                                      andBuffer:reinterpret_cast<Byte *>(&rawFrame)
                                                        andSize:sizeof(rawFrame)
                                                     andTimeOut:kReadTimeoutMs];
    if (result != kIOReturnSuccess) {
        reportError(tr("Failed to send CAN frame over InnoMaker USB2CAN (IOReturn %1).")
                            .arg(static_cast<qulonglong>(result)),
                    QCanBusDevice::WriteError);
        return false;
    }

    emit framesWritten(1);
    return true;
}

QString InnoMakerCanBackend::interpretErrorFrame(const QCanBusFrame &frame)
{
    if (frame.frameType() != QCanBusFrame::ErrorFrame)
        return QString();

    QStringList messages;
    const auto errors = frame.error();
    const QByteArray payload = frame.payload();

    if (errors.testFlag(QCanBusFrame::ControllerRestartError))
        messages.append(QStringLiteral("Controller restarted"));
    if (errors.testFlag(QCanBusFrame::BusOffError))
        messages.append(QStringLiteral("Bus off"));
    if (errors.testFlag(QCanBusFrame::BusError))
        messages.append(QStringLiteral("Bus error"));
    if (errors.testFlag(QCanBusFrame::ControllerError)) {
        messages.append(QStringLiteral("Controller error"));
        if (payload.size() > 1) {
            const auto control = static_cast<quint8>(payload.at(1));
            if (control & CAN_ERR_CRTL_RX_OVERFLOW)
                messages.append(QStringLiteral("RX overflow"));
            if (control & CAN_ERR_CRTL_TX_OVERFLOW)
                messages.append(QStringLiteral("TX overflow"));
            if (control & CAN_ERR_CRTL_RX_WARNING)
                messages.append(QStringLiteral("RX warning"));
            if (control & CAN_ERR_CRTL_TX_WARNING)
                messages.append(QStringLiteral("TX warning"));
            if (control & CAN_ERR_CRTL_RX_PASSIVE)
                messages.append(QStringLiteral("RX passive"));
            if (control & CAN_ERR_CRTL_TX_PASSIVE)
                messages.append(QStringLiteral("TX passive"));
        }
    }

    if (messages.isEmpty())
        messages.append(QStringLiteral("Unknown CAN controller error"));

    return messages.join(QStringLiteral(", "));
}

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
QCanBusDeviceInfo InnoMakerCanBackend::deviceInfo() const
#else
QCanBusDeviceInfo InnoMakerCanBackend::deviceInfo() const
#endif
{
    return createDeviceInfoCompat(m_interfaceName,
                                  m_device ? deviceSerial(m_device) : QString(),
                                  deviceDescription(),
                                  qMax(m_deviceIndex, 0),
                                  false,
                                  false);
}

bool InnoMakerCanBackend::hasBusStatus() const
{
    return false;
}

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
void InnoMakerCanBackend::setConfigurationParameter(ConfigurationKey key, const QVariant &value)
#else
void InnoMakerCanBackend::setConfigurationParameter(int key, const QVariant &value)
#endif
{
    if (key == QCanBusDevice::CanFdKey && value.toBool()) {
        reportError(tr("InnoMaker macOS backend does not support CAN FD."),
                    QCanBusDevice::ConfigurationError);
        return;
    }

    QCanBusDevice::setConfigurationParameter(key, value);
}

bool InnoMakerCanBackend::open()
{
    if (m_deviceIndex < 0) {
        reportError(tr("Invalid InnoMaker interface name: %1").arg(m_interfaceName),
                    QCanBusDevice::ConnectionError);
        setState(QCanBusDevice::UnconnectedState);
        return false;
    }

    @autoreleasepool {
        m_usbIo = [[UsbIO alloc] init];
        if ([m_usbIo scanInnoMakerDevices] != kIOReturnSuccess) {
            reportError(tr("Failed to enumerate InnoMaker USB2CAN devices."),
                        QCanBusDevice::ConnectionError);
            m_usbIo = nil;
            setState(QCanBusDevice::UnconnectedState);
            return false;
        }

        const NSUInteger count = [m_usbIo getInnoMakerDeviceCount];
        if (m_deviceIndex >= static_cast<int>(count)) {
            reportError(tr("Requested InnoMaker device %1 is not available.").arg(m_interfaceName),
                        QCanBusDevice::ConnectionError);
            m_usbIo = nil;
            setState(QCanBusDevice::UnconnectedState);
            return false;
        }

        m_device = [m_usbIo getInnoMakerDevice:static_cast<UInt8>(m_deviceIndex)];
        if (!m_device || ![m_usbIo openInnoMakerDevice:m_device]) {
            reportError(tr("Failed to open InnoMaker device %1.").arg(m_interfaceName),
                        QCanBusDevice::ConnectionError);
            m_device = nil;
            m_usbIo = nil;
            setState(QCanBusDevice::UnconnectedState);
            return false;
        }

        if (!configureDevice()) {
            if (m_device)
                [m_usbIo closeInnoMakerDevice:m_device];
            m_device = nil;
            m_usbIo = nil;
            setState(QCanBusDevice::UnconnectedState);
            return false;
        }

        clearError();
        setState(QCanBusDevice::ConnectedState);
        startReadLoop();
        return true;
    }
}

void InnoMakerCanBackend::close()
{
    stopReadLoop();

    @autoreleasepool {
        if (m_usbIo && m_device) {
            [m_usbIo UrbResetDevice:m_device];
            [m_usbIo closeInnoMakerDevice:m_device];
        }
        m_device = nil;
        m_usbIo = nil;
    }

    setState(QCanBusDevice::UnconnectedState);
}

QString InnoMakerCanBackend::pluginKey()
{
    return QStringLiteral("innomakerusb2can");
}

int InnoMakerCanBackend::parseInterfaceIndex(const QString &interfaceName)
{
    const QRegularExpression match(QStringLiteral("^can(\\d+)$"));
    const auto result = match.match(interfaceName.trimmed());
    if (!result.hasMatch())
        return -1;
    return result.captured(1).toInt();
}

QString InnoMakerCanBackend::interfaceNameForIndex(int index)
{
    return QStringLiteral("can%1").arg(index);
}

QString InnoMakerCanBackend::deviceDescription()
{
    return QStringLiteral("InnoMaker USB2CAN");
}

std::optional<InnoMakerCanBackend::BitTiming> InnoMakerCanBackend::bitrateToTiming(quint32 bitrate)
{
    switch (bitrate) {
    case 20000: return BitTiming{6, 7, 2, 1, 150};
    case 33333: return BitTiming{3, 3, 1, 1, 180};
    case 40000: return BitTiming{6, 7, 2, 1, 75};
    case 50000: return BitTiming{6, 7, 2, 1, 60};
    case 66666: return BitTiming{3, 3, 1, 1, 90};
    case 80000: return BitTiming{3, 3, 1, 1, 75};
    case 83333: return BitTiming{3, 3, 1, 1, 72};
    case 100000: return BitTiming{6, 7, 2, 1, 30};
    case 125000: return BitTiming{6, 7, 2, 1, 24};
    case 200000: return BitTiming{6, 7, 2, 1, 15};
    case 250000: return BitTiming{6, 7, 2, 1, 12};
    case 400000: return BitTiming{3, 3, 1, 1, 15};
    case 500000: return BitTiming{6, 7, 2, 1, 6};
    case 666000: return BitTiming{3, 3, 2, 1, 8};
    case 666666: return BitTiming{3, 3, 2, 1, 8};
    case 800000: return BitTiming{7, 8, 4, 1, 3};
    case 1000000: return BitTiming{5, 6, 4, 1, 3};
    default: return std::nullopt;
    }
}

QString InnoMakerCanBackend::deviceSerial(InnoMakerDevice *device)
{
    if (!device)
        return QString();
    return hexString(device.deviceID);
}

QCanBusFrame InnoMakerCanBackend::toFrame(const struct innomaker_host_frame &raw)
{
    QCanBusFrame frame;
    frame.setTimeStamp(QCanBusFrame::TimeStamp::fromMicroSeconds(raw.timestamp_us));

    if (raw.can_id & CAN_ERR_FLAG) {
        frame.setFrameType(QCanBusFrame::ErrorFrame);
        frame.setError(toFrameErrors(raw.can_id));
    } else if (raw.can_id & CAN_RTR_FLAG) {
        frame.setFrameType(QCanBusFrame::RemoteRequestFrame);
    } else {
        frame.setFrameType(QCanBusFrame::DataFrame);
    }

    frame.setExtendedFrameFormat(raw.can_id & CAN_EFF_FLAG);
    frame.setFrameId(raw.can_id & CAN_EFF_MASK);
    frame.setPayload(QByteArray(reinterpret_cast<const char *>(raw.data), raw.can_dlc));
    return frame;
}

QCanBusFrame::FrameErrors InnoMakerCanBackend::toFrameErrors(quint32 canId)
{
    QCanBusFrame::FrameErrors errors = QCanBusFrame::NoError;

    if (canId & CAN_ERR_RESTARTED)
        errors |= QCanBusFrame::ControllerRestartError;
    if (canId & CAN_ERR_BUSOFF)
        errors |= QCanBusFrame::BusOffError;
    if (canId & CAN_ERR_CRTL)
        errors |= QCanBusFrame::ControllerError;

    if (errors == QCanBusFrame::NoError)
        errors |= QCanBusFrame::UnknownError;

    return errors;
}

bool InnoMakerCanBackend::configureDevice()
{
    if (!m_usbIo || !m_device) {
        reportError(tr("InnoMaker device handle is not initialized."), QCanBusDevice::ConnectionError);
        return false;
    }

    if (configurationParameter(QCanBusDevice::CanFdKey).toBool()) {
        reportError(tr("InnoMaker macOS backend does not support CAN FD."),
                    QCanBusDevice::ConfigurationError);
        return false;
    }

    const quint32 bitrate = configurationParameter(QCanBusDevice::BitRateKey).toUInt();
    const auto timing = bitrateToTiming(bitrate);
    if (!timing.has_value()) {
        reportError(tr("Unsupported bitrate %1 for InnoMaker macOS backend.").arg(bitrate),
                    QCanBusDevice::ConfigurationError);
        return false;
    }

    struct innomaker_device_bittiming rawTiming = {};
    rawTiming.prop_seg = timing->propSeg;
    rawTiming.phase_seg1 = timing->phaseSeg1;
    rawTiming.phase_seg2 = timing->phaseSeg2;
    rawTiming.sjw = timing->sjw;
    rawTiming.brp = timing->brp;

    if (![m_usbIo UrbSetupDevice:m_device mode:configuredMode() bittiming:rawTiming]) {
        reportError(tr("Failed to configure InnoMaker device for bitrate %1.").arg(bitrate),
                    QCanBusDevice::ConfigurationError);
        return false;
    }

    return true;
}

void InnoMakerCanBackend::startReadLoop()
{
    stopReadLoop();
    m_running.store(true, std::memory_order_release);
    m_readThread = std::thread([this]() { readLoop(); });
}

void InnoMakerCanBackend::stopReadLoop()
{
    m_running.store(false, std::memory_order_release);
    if (m_readThread.joinable())
        m_readThread.join();
}

void InnoMakerCanBackend::readLoop()
{
    while (m_running.load(std::memory_order_acquire)) {
        @autoreleasepool {
            if (!m_usbIo || !m_device)
                return;

            struct innomaker_host_frame rawFrame = {};
            const IOReturn result = [m_usbIo syncGetInnoMakerDeviceBuf:m_device
                                                             andBuffer:reinterpret_cast<Byte *>(&rawFrame)
                                                               andSize:sizeof(rawFrame)
                                                            andTimeOut:kReadTimeoutMs];
            if (!m_running.load(std::memory_order_acquire))
                return;

            if (result != kIOReturnSuccess)
                continue;

            if (rawFrame.echo_id != kInvalidEchoId)
                continue;

            queueReceivedFrame(toFrame(rawFrame));
        }
    }
}

void InnoMakerCanBackend::queueReceivedFrame(const QCanBusFrame &frame)
{
    QMetaObject::invokeMethod(this, [this, frame]() {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        enqueueReceivedFrames(QList<QCanBusFrame>{frame});
#else
        enqueueReceivedFrames(QVector<QCanBusFrame>{frame});
#endif
    }, Qt::QueuedConnection);
}

void InnoMakerCanBackend::reportError(const QString &message, CanBusError error)
{
    setError(message, error);
}

UsbCanMode InnoMakerCanBackend::configuredMode() const
{
    const quint32 userMode = configurationParameter(QCanBusDevice::UserKey).toUInt();
    if (userMode & kListenOnlyFlag)
        return UsbCanModeListenOnly;

    if (configurationParameter(QCanBusDevice::LoopbackKey).toBool())
        return UsbCanModeLoopback;

    return UsbCanModeNormal;
}

QT_END_NAMESPACE
