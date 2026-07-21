#include "innomakercanbackend.h"

#include <QCanBusFactory>
#include <QtGlobal>

QT_BEGIN_NAMESPACE

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
class InnoMakerCanBusPlugin : public QObject, public QCanBusFactory
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QCanBusFactory" FILE "plugin.json")
    Q_INTERFACES(QCanBusFactory)
#else
class InnoMakerCanBusPlugin : public QObject, public QCanBusFactoryV2
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QCanBusFactory" FILE "plugin.json")
    Q_INTERFACES(QCanBusFactory QCanBusFactoryV2)
#endif

public:
    QList<QCanBusDeviceInfo> availableDevices(QString *errorMessage) const override
    {
        return InnoMakerCanBackend::interfaces(errorMessage);
    }

    QCanBusDevice *createDevice(const QString &interfaceName, QString *errorMessage) const override
    {
        if (InnoMakerCanBackend::parseInterfaceIndex(interfaceName) < 0) {
            if (errorMessage) {
                *errorMessage = QStringLiteral("Invalid InnoMaker interface name '%1'. Expected canN.")
                        .arg(interfaceName);
            }
            return nullptr;
        }

        return new InnoMakerCanBackend(interfaceName);
    }
};

QT_END_NAMESPACE

#include <innomakercanplugin.moc>
