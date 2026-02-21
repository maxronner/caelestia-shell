#include "requests.hpp"

#include <qnetworkaccessmanager.h>
#include <qnetworkreply.h>
#include <qnetworkrequest.h>

namespace caelestia {

Requests::Requests(QObject* parent)
    : QObject(parent)
    , m_manager(new QNetworkAccessManager(this)) {}

void Requests::get(const QUrl& url, QJSValue onSuccess, QJSValue onError) const {
    if (!onSuccess.isCallable()) {
        qWarning() << "Requests::get: onSuccess is not callable";
        return;
    }

    // Restrict to http/https only. Qt's QNetworkAccessManager also handles file://
    // and qrc:// schemes natively, which would allow reading arbitrary local files
    // if called with a crafted URL from QML.
    const QString scheme = url.scheme().toLower();
    if (scheme != QLatin1String("http") && scheme != QLatin1String("https")) {
        qWarning() << "Requests::get: rejected non-http(s) URL scheme:" << scheme;
        if (onError.isCallable()) {
            onError.call({ QStringLiteral("Only http and https URLs are permitted") });
        }
        return;
    }

    QNetworkRequest request(url);
    auto reply = m_manager->get(request);

    QObject::connect(reply, &QNetworkReply::finished, [reply, onSuccess, onError]() {
        if (reply->error() == QNetworkReply::NoError) {
            onSuccess.call({ QString(reply->readAll()) });
        } else if (onError.isCallable()) {
            onError.call({ reply->errorString() });
        } else {
            qWarning() << "Requests::get: request failed with error" << reply->errorString();
        }

        reply->deleteLater();
    });
}

} // namespace caelestia
