#pragma once

#include "USBIO+USBCAN.h"

#include <QCanBusDevice>
#include <QtGlobal>

#include <atomic>
#include <memory>
#include <optional>
#include <thread>

QT_BEGIN_NAMESPACE

class InnoMakerCanBackend : public QCanBusDevice
{
public:
    struct BitTiming {
        quint32 propSeg;
        quint32 phaseSeg1;
        quint32 phaseSeg2;
        quint32 sjw;
        quint32 brp;
    };

    explicit InnoMakerCanBackend(const QString &interfaceName, QObject *parent = nullptr);
    ~InnoMakerCanBackend() override;

    static QList<QCanBusDeviceInfo> interfaces(QString *errorMessage = nullptr);
    static QCanBusDeviceInfo interfaceInfo(int deviceIndex, QString *errorMessage = nullptr);
    static int parseInterfaceIndex(const QString &interfaceName);

    bool writeFrame(const QCanBusFrame &frame) override;
    QString interpretErrorFrame(const QCanBusFrame &frame) override;
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    QCanBusDeviceInfo deviceInfo() const override;
    bool hasBusStatus() const override;
#else
    QCanBusDeviceInfo deviceInfo() const;
    bool hasBusStatus() const;
#endif

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    void setConfigurationParameter(ConfigurationKey key, const QVariant &value) override;
#else
    void setConfigurationParameter(int key, const QVariant &value) override;
#endif

protected:
    bool open() override;
    void close() override;

private:
    static QString pluginKey();
    static QCanBusDeviceInfo createDeviceInfoCompat(const QString &name,
                                                    const QString &serialNumber,
                                                    const QString &description,
                                                    int channel,
                                                    bool isVirtual,
                                                    bool isFlexibleDataRateCapable);
    static QCanBusDeviceInfo createDeviceInfoCompat(const QString &name,
                                                    bool isVirtual,
                                                    bool isFlexibleDataRateCapable);
    static QString interfaceNameForIndex(int index);
    static QString deviceDescription();
    static std::optional<BitTiming> bitrateToTiming(quint32 bitrate);
    static QString deviceSerial(InnoMakerDevice *device);
    static QCanBusFrame toFrame(const struct innomaker_host_frame &raw);
    static QCanBusFrame::FrameErrors toFrameErrors(quint32 canId);

    bool configureDevice();
    void startReadLoop();
    void stopReadLoop();
    void readLoop();
    void queueReceivedFrame(const QCanBusFrame &frame);
    void reportError(const QString &message, CanBusError error);
    UsbCanMode configuredMode() const;

    const QString m_interfaceName;
    const int m_deviceIndex;

    UsbIO *m_usbIo = nullptr;
    InnoMakerDevice *m_device = nullptr;
    std::atomic_bool m_running = false;
    std::thread m_readThread;
    std::atomic_uint m_nextEchoId = 0;
};

QT_END_NAMESPACE
