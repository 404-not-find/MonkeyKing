
import UIKit
import WebKit

public class MonkeyKing: NSObject {

    public typealias ResponseJSON = [String: Any]

    public typealias DeliverCompletionHandler = (Result<ResponseJSON?, Error>) -> Void
    public typealias LaunchCompletionHandler = (Result<Void, Error>) -> Void
    public typealias LaunchFromWeChatMiniAppCompletionHandler = (Result<String, Error>) -> Void
    public typealias OAuthCompletionHandler = (Result<ResponseJSON?, Error>) -> Void
    public typealias OAuthFromWeChatCodeCompletionHandler = (Result<String, Error>) -> Void
    public typealias OpenSchemeCompletionHandler = (Result<URL, Error>) -> Void
    public typealias PayCompletionHandler = (Result<Void, Error>) -> Void

    static let shared = MonkeyKing()

    var webView: WKWebView?

    var accountSet = Set<Account>()

    var deliverCompletionHandler: DeliverCompletionHandler?
    var launchCompletionHandler: LaunchCompletionHandler?
    var launchFromWeChatMiniAppCompletionHandler: LaunchFromWeChatMiniAppCompletionHandler?
    var oauthCompletionHandler: OAuthCompletionHandler?
    var oauthFromWeChatCodeCompletionHandler: OAuthFromWeChatCodeCompletionHandler?
    var openSchemeCompletionHandler: OpenSchemeCompletionHandler?
    var payCompletionHandler: PayCompletionHandler?

    private override init() {}

    public enum Account: Hashable {
        case weChat(appID: String, appKey: String?, miniAppID: String?)
        case qq(appID: String)
        case weibo(appID: String, appKey: String, redirectURL: String)
        case pocket(appID: String)
        case alipay(appID: String)
        case twitter(appID: String, appKey: String, redirectURL: String)

        public var isAppInstalled: Bool {
            switch self {
            case .weChat:
                return MonkeyKing.SupportedPlatform.weChat.isAppInstalled
            case .qq:
                return MonkeyKing.SupportedPlatform.qq.isAppInstalled
            case .weibo:
                return MonkeyKing.SupportedPlatform.weibo.isAppInstalled
            case .pocket:
                return MonkeyKing.SupportedPlatform.pocket.isAppInstalled
            case .alipay:
                return MonkeyKing.SupportedPlatform.alipay.isAppInstalled
            case .twitter:
                return MonkeyKing.SupportedPlatform.twitter.isAppInstalled
            }
        }

        public var appID: String {
            switch self {
            case .weChat(let appID, _, _):
                return appID
            case .qq(let appID):
                return appID
            case .weibo(let appID, _, _):
                return appID
            case .pocket(let appID):
                return appID
            case .alipay(let appID):
                return appID
            case .twitter(let appID, _, _):
                return appID
            }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(appID)
        }

        public var canWebOAuth: Bool {
            switch self {
            case .qq, .weibo, .pocket, .weChat, .twitter:
                return true
            case .alipay:
                return false
            }
        }

        public static func == (lhs: MonkeyKing.Account, rhs: MonkeyKing.Account) -> Bool {
            switch (lhs, rhs) {
            case (.weChat(let lappID, _, _), .weChat(let rappID, _, _)),
                 (.qq(let lappID), .qq(let rappID)),
                 (.weibo(let lappID, _, _), .weibo(let rappID, _, _)),
                 (.pocket(let lappID), .pocket(let rappID)),
                 (.alipay(let lappID), .alipay(let rappID)),
                 (.twitter(let lappID, _, _), .twitter(let rappID, _, _)):
                return lappID == rappID
            case (.weChat, _),
                 (.qq, _),
                 (.weibo, _),
                 (.pocket, _),
                 (.alipay, _),
                 (.twitter, _):
                return false
            }
        }
    }

    public enum SupportedPlatform {
        case weChat
        case qq
        case weibo
        case pocket
        case alipay
        case twitter

        public var isAppInstalled: Bool {
            switch self {
            case .weChat:
                return shared.canOpenURL(urlString: "weixin://")
            case .qq:
                return shared.canOpenURL(urlString: "mqqapi://")
            case .weibo:
                return shared.canOpenURL(urlString: "weibosdk://request")
            case .pocket:
                return shared.canOpenURL(urlString: "pocket-oauth-v1://")
            case .alipay:
                return shared.canOpenURL(urlString: "alipayshare://") || shared.canOpenURL(urlString: "alipay://")
            case .twitter:
                return shared.canOpenURL(urlString: "twitter://")
            }
        }
    }

    public class func registerAccount(_ account: Account) {
        guard account.isAppInstalled || account.canWebOAuth else { return }
        for oldAccount in MonkeyKing.shared.accountSet {
            switch oldAccount {
            case .weChat:
                if case .weChat = account { shared.accountSet.remove(oldAccount) }
            case .qq:
                if case .qq = account { shared.accountSet.remove(oldAccount) }
            case .weibo:
                if case .weibo = account { shared.accountSet.remove(oldAccount) }
            case .pocket:
                if case .pocket = account { shared.accountSet.remove(oldAccount) }
            case .alipay:
                if case .alipay = account { shared.accountSet.remove(oldAccount) }
            case .twitter:
                if case .twitter = account { shared.accountSet.remove(oldAccount) }
            }
        }
        shared.accountSet.insert(account)
    }

    public class func registerLaunchFromWeChatMiniAppHandler(_ handler: @escaping LaunchFromWeChatMiniAppCompletionHandler) {
        shared.launchFromWeChatMiniAppCompletionHandler = handler
    }
}

// MARK: OpenURL Handler

extension MonkeyKing {

    public class func handleOpenURL(_ url: URL) -> Bool {

        guard let urlScheme = url.scheme else { return false }

        // WeChat
        if urlScheme.hasPrefix("wx") {
            let urlString = url.absoluteString
            // OAuth
            if urlString.contains("state=Weixinauth") {
                let queryDictionary = url.monkeyking_queryDictionary
                guard let code = queryDictionary["code"] else {
                    shared.oauthFromWeChatCodeCompletionHandler = nil
                    return false
                }
                // Login Succcess
                if let halfOauthCompletion = shared.oauthFromWeChatCodeCompletionHandler {
                    halfOauthCompletion(.success(code))
                    shared.oauthFromWeChatCodeCompletionHandler = nil
                } else {
                    fetchWeChatOAuthInfoByCode(code: code) { result in
                        shared.oauthCompletionHandler?(result)
                    }
                }
                return true
            }
            // SMS OAuth
            if urlString.contains("wapoauth") {
                let queryDictionary = url.monkeyking_queryDictionary
                guard let m = queryDictionary["m"] else { return false }
                guard let t = queryDictionary["t"] else { return false }
                guard let account = shared.accountSet[.weChat] else { return false }
                let appID = account.appID
                let urlString = "https://open.weixin.qq.com/connect/smsauthorize?appid=\(appID)&redirect_uri=\(appID)%3A%2F%2Foauth&response_type=code&scope=snsapi_message,snsapi_userinfo,snsapi_friend,snsapi_contact&state=xxx&uid=1926559385&m=\(m)&t=\(t)"
                addWebView(withURLString: urlString)
                return true
            }
            // Pay
            if urlString.contains("://pay/") {
                let queryDictionary = url.monkeyking_queryDictionary

                guard let ret = queryDictionary["ret"] else {
                    shared.payCompletionHandler?(.failure(.apiRequest(.missingParameter)))
                    return false
                }

                let result = (ret == "0")

                if result {
                    shared.payCompletionHandler?(.success(()))
                } else {
                    shared.payCompletionHandler?(.failure(.apiRequest(.unrecognizedError(response: queryDictionary))))
                }

                return result
            }

            if let data = UIPasteboard.general.data(forPasteboardType: "content") {
                if let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {

                    guard
                        let account = shared.accountSet[.weChat],
                        let info = dict[account.appID] as? [String: Any],
                        let result = info["result"] as? String,
                        let resultCode = Int(result) else {
                        return false
                    }

                    // OAuth Failed
                    if let state = info["state"] as? String, state == "Weixinauth", resultCode != 0 {
                        let error: Error = resultCode == -2
                            ? .userCancelled
                            : .sdk(.other(code: result))
                        shared.deliverCompletionHandler?(.failure(error))
                        return false
                    }

                    let success = (resultCode == 0)

                    // Share or Launch Mini App
                    let messageExtKey = "messageExt"
                    if success {
                        if let messageExt = info[messageExtKey] as? String {
                            shared.launchFromWeChatMiniAppCompletionHandler?(.success(messageExt))
                        } else {
                            shared.deliverCompletionHandler?(.success(nil))
                        }
                    } else {
                        if let messageExt = info[messageExtKey] as? String {
                            shared.launchFromWeChatMiniAppCompletionHandler?(.success(messageExt))
                            return true
                        } else {
                            let error: Error = resultCode == -2
                                ? .userCancelled
                                : .sdk(.other(code: result))
                            shared.deliverCompletionHandler?(.failure(error))
                        }
                    }

                    return success
                }
            }

            return false
        }

        // QQ Share
        if urlScheme.hasPrefix("QQ") {
            guard let errorDescription = url.monkeyking_queryDictionary["error"] else { return false }
            let success = (errorDescription == "0")
            if success {
                shared.deliverCompletionHandler?(.success(nil))
            } else {
                let error: Error = errorDescription == "-4"
                    ? .userCancelled
                    : .sdk(.other(code: errorDescription))
                shared.deliverCompletionHandler?(.failure(error))
            }
            return success
        }

        // QQ OAuth
        if urlScheme.hasPrefix("tencent") {
            guard let account = shared.accountSet[.qq] else { return false }
            guard
                let data = UIPasteboard.general.data(forPasteboardType: "com.tencent.tencent\(account.appID)"),
                let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: Any] else {
                shared.oauthCompletionHandler?(.failure(.sdk(.deserializeFailed)))
                return false
            }
            guard let result = info["ret"] as? Int, result == 0 else {
                let error: Error
                if let errorDomatin = info["user_cancelled"] as? String, errorDomatin == "YES" {
                    error = .userCancelled
                } else {
                    error = .apiRequest(.unrecognizedError(response: nil))
                }
                shared.oauthCompletionHandler?(.failure(error))
                return false
            }

            shared.oauthCompletionHandler?(.success(info))
            return true
        }

        // Weibo
        if urlScheme.hasPrefix("wb") {
            let items = UIPasteboard.general.items
            var results = [String: Any]()
            for item in items {
                for (key, value) in item {
                    if let valueData = value as? Data, key == "transferObject" {
                        results[key] = NSKeyedUnarchiver.unarchiveObject(with: valueData)
                    }
                }
            }
            guard
                let responseInfo = results["transferObject"] as? [String: Any],
                let type = responseInfo["__class"] as? String else {
                return false
            }
            guard let statusCode = responseInfo["statusCode"] as? Int else {
                return false
            }
            switch type {
            // OAuth
            case "WBAuthorizeResponse":
                if statusCode != 0 {
                    shared.oauthCompletionHandler?(.failure(.apiRequest(.unrecognizedError(response: responseInfo))))
                    return false
                }

                shared.oauthCompletionHandler?(.success(responseInfo))
                return true
            // Share
            case "WBSendMessageToWeiboResponse":
                let success = (statusCode == 0)
                if success {
                    shared.deliverCompletionHandler?(.success(nil))
                } else {
                    let error: Error = statusCode == -1
                        ? .userCancelled
                        : .sdk(.other(code: String(statusCode)))
                    shared.deliverCompletionHandler?(.failure(error))
                }
                return success
            default:
                break
            }
        }

        // Pocket OAuth
        if urlScheme.hasPrefix("pocketapp") {
            shared.oauthCompletionHandler?(.success(nil))
            return true
        }

        // Alipay
        let account = shared.accountSet[.alipay]
        if let appID = account?.appID, urlScheme == "ap" + appID || urlScheme == "apoauth" + appID {
            let urlString = url.absoluteString
            if urlString.contains("//safepay/?") {

                guard
                    let query = url.query,
                    let response = query.monkeyking_urlDecodedString?.data(using: .utf8),
                    let json = response.monkeyking_json,
                    let memo = json["memo"] as? [String: Any],
                    let status = memo["ResultStatus"] as? String
                else {
                    shared.oauthCompletionHandler?(.failure(.apiRequest(.missingParameter)))
                    shared.payCompletionHandler?(.failure(.apiRequest(.missingParameter)))
                    return false
                }

                if status != "9000" {
                    shared.oauthCompletionHandler?(.failure(.apiRequest(.invalidParameter)))
                    shared.payCompletionHandler?(.failure(.apiRequest(.invalidParameter)))
                    return false
                }

                if urlScheme == "apoauth" + appID { // OAuth
                    let resultStr = memo["result"] as? String ?? ""
                    let urlStr = "https://www.example.com?" + resultStr
                    let resultDic = URL(string: urlStr)?.monkeyking_queryDictionary ?? [:]
                    if let _ = resultDic["auth_code"], let _ = resultDic["scope"] {
                        shared.oauthCompletionHandler?(.success(resultDic))
                        return true
                    }
                    shared.oauthCompletionHandler?(.failure(.apiRequest(.unrecognizedError(response: resultDic))))
                    return false
                } else { // Pay
                    shared.payCompletionHandler?(.success(()))
                }
                return true
            } else { // Share
                guard
                    let data = UIPasteboard.general.data(forPasteboardType: "com.alipay.openapi.pb.resp.\(appID)"),
                    let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                    let objects = dict["$objects"] as? NSArray,
                    let result = objects[12] as? Int else {
                    return false
                }
                let success = (result == 0)
                if success {
                    shared.deliverCompletionHandler?(.success(nil))
                } else {
                    shared.deliverCompletionHandler?(.failure(.sdk(.other(code: String(result))))) // TODO: user cancelled
                }
                return success
            }
        }

        if let handler = shared.openSchemeCompletionHandler {
            handler(.success(url))
            return true
        }

        return false
    }
}

// MARK: Share Message

extension MonkeyKing {
    public enum MiniAppType: Int {
        case release = 0
        case test = 1
        case preview = 2
    }

    public enum Media {
        case url(URL)
        case image(UIImage)
        case imageData(Data)
        case gif(Data)
        case audio(audioURL: URL, linkURL: URL?)
        case video(URL)
        case file(Data, fileExt: String?) /// file extension for wechat file share
        case miniApp(url: URL, path: String, withShareTicket: Bool, type: MiniAppType)
    }

    public typealias Info = (title: String?, description: String?, thumbnail: UIImage?, media: Media?)

    public enum Message {

        public enum WeChatSubtype {
            case session(info: Info)
            case timeline(info: Info)
            case favorite(info: Info)

            var scene: String {
                switch self {
                case .session:
                    return "0"
                case .timeline:
                    return "1"
                case .favorite:
                    return "2"
                }
            }

            var info: Info {
                switch self {
                case .session(let info):
                    return info
                case .timeline(let info):
                    return info
                case .favorite(let info):
                    return info
                }
            }
        }

        case weChat(WeChatSubtype)

        public enum QQSubtype {
            case friends(info: Info)
            case zone(info: Info)
            case favorites(info: Info)
            case dataline(info: Info)

            var scene: Int {
                switch self {
                case .friends:
                    return 0x00
                case .zone:
                    return 0x01
                case .favorites:
                    return 0x08
                case .dataline:
                    return 0x10
                }
            }

            var info: Info {
                switch self {
                case .friends(let info):
                    return info
                case .zone(let info):
                    return info
                case .favorites(let info):
                    return info
                case .dataline(let info):
                    return info
                }
            }
        }

        case qq(QQSubtype)

        public enum WeiboSubtype {
            case `default`(info: Info, accessToken: String?)

            var info: Info {
                switch self {
                case .default(let info, _):
                    return info
                }
            }

            var accessToken: String? {
                switch self {
                case .default(_, let accessToken):
                    return accessToken
                }
            }
        }

        case weibo(WeiboSubtype)

        public enum AlipaySubtype {
            case friends(info: Info)
            case timeline(info: Info)

            var scene: NSNumber {
                switch self {
                case .friends:
                    return 0
                case .timeline:
                    return 1
                }
            }

            var info: Info {
                switch self {
                case .friends(let info):
                    return info
                case .timeline(let info):
                    return info
                }
            }
        }

        case alipay(AlipaySubtype)

        public enum TwitterSubtype {
            case `default`(info: Info, mediaIDs: [String]?, accessToken: String?, accessTokenSecret: String?)

            var info: Info {
                switch self {
                case .default(let info, _, _, _):
                    return info
                }
            }

            var mediaIDs: [String]? {
                switch self {
                case .default(_, let mediaIDs, _, _):
                    return mediaIDs
                }
            }

            var accessToken: String? {
                switch self {
                case .default(_, _, let accessToken, _):
                    return accessToken
                }
            }

            var accessTokenSecret: String? {
                switch self {
                case .default(_, _, _, let accessTokenSecret):
                    return accessTokenSecret
                }
            }
        }

        case twitter(TwitterSubtype)

        public var canBeDelivered: Bool {
            guard let account = shared.accountSet[self] else { return false }
            switch account {
            case .weibo, .twitter:
                return true
            default:
                break
            }
            return account.isAppInstalled
        }
    }

    public class func deliver(_ message: Message, completionHandler: @escaping DeliverCompletionHandler) {
        guard message.canBeDelivered else {
            completionHandler(.failure(.noApp))
            return
        }
        guard let account = shared.accountSet[message] else {
            completionHandler(.failure(.noAccount))
            return
        }

        shared.deliverCompletionHandler = completionHandler
        shared.payCompletionHandler = nil
        shared.oauthCompletionHandler = nil
        shared.openSchemeCompletionHandler = nil

        let appID = account.appID
        switch message {
        case .weChat(let type):
            var weChatMessageInfo: [String: Any] = [
                "result": "1",
                "returnFromApp": "0",
                "scene": type.scene,
                "sdkver": "1.5",
                "command": "1010",
            ]
            let info = type.info
            if let title = info.title {
                weChatMessageInfo["title"] = title
            }
            if let description = info.description {
                weChatMessageInfo["description"] = description
            }
            if let thumbnailImage = info.thumbnail {
                weChatMessageInfo["thumbData"] = thumbnailImage.monkeyking_compressedImageData
            }
            if let media = info.media {
                switch media {
                case .url(let url):
                    weChatMessageInfo["objectType"] = "5"
                    weChatMessageInfo["mediaUrl"] = url.absoluteString
                case .image(let image):
                    weChatMessageInfo["objectType"] = "2"
                    if let imageData = image.jpegData(compressionQuality: 0.9) {
                        weChatMessageInfo["fileData"] = imageData
                    }
                case .imageData(let imageData):
                    weChatMessageInfo["objectType"] = "2"
                    weChatMessageInfo["fileData"] = imageData
                case .gif(let data):
                    weChatMessageInfo["objectType"] = "8"
                    weChatMessageInfo["fileData"] = data
                case .audio(let audioURL, let linkURL):
                    weChatMessageInfo["objectType"] = "3"
                    if let urlString = linkURL?.absoluteString {
                        weChatMessageInfo["mediaUrl"] = urlString
                    }
                    weChatMessageInfo["mediaDataUrl"] = audioURL.absoluteString
                case .video(let url):
                    weChatMessageInfo["objectType"] = "4"
                    weChatMessageInfo["mediaUrl"] = url.absoluteString
                case .miniApp(let url, let path, let withShareTicket, let type):
                    if case .weChat(let appID, _, let miniProgramID) = account {
                        weChatMessageInfo["objectType"] = "36"
                        if let hdThumbnailImage = info.thumbnail {
                            weChatMessageInfo["hdThumbData"] = hdThumbnailImage.monkeyking_resetSizeOfImageData(maxSize: 127 * 1024)
                        }
                        weChatMessageInfo["mediaUrl"] = url.absoluteString
                        weChatMessageInfo["appBrandPath"] = path
                        weChatMessageInfo["withShareTicket"] = withShareTicket
                        weChatMessageInfo["miniprogramType"] = type.rawValue
                        if let miniProgramID = miniProgramID {
                            weChatMessageInfo["appBrandUserName"] = miniProgramID
                        } else {
                            fatalError("Missing `miniProgramID`!")
                        }
                    }
                case .file(let fileData, let fileExt):
                    weChatMessageInfo["objectType"] = "6"
                    weChatMessageInfo["fileData"] = fileData
                    weChatMessageInfo["fileExt"] = fileExt

                    if let fileExt = fileExt, let title = info.title {
                        let suffix = ".\(fileExt)"
                        weChatMessageInfo["title"] = title.hasSuffix(suffix) ? title : title + suffix
                    }
                }
            } else { // Text Share
                weChatMessageInfo["command"] = "1020"
            }
            var weChatMessage: [String: Any] = [appID: weChatMessageInfo]
            if let oldText = UIPasteboard.general.oldText {
                weChatMessage["old_text"] = oldText
            }
            guard let data = try? PropertyListSerialization.data(fromPropertyList: weChatMessage, format: .binary, options: .init()) else { return }
            UIPasteboard.general.setData(data, forPasteboardType: "content")
            let weChatSchemeURLString = "weixin://app/\(appID)/sendreq/?"
            openURL(urlString: weChatSchemeURLString) { flag in
                if flag { return }
                completionHandler(.failure(.sdk(.invalidURLScheme)))
            }
        case .qq(let type):
            let callbackName = appID.monkeyking_qqCallbackName
            var qqSchemeURLString = "mqqapi://share/to_fri?"
            if let encodedAppDisplayName = Bundle.main.monkeyking_displayName?.monkeyking_base64EncodedString {
                qqSchemeURLString += "thirdAppDisplayName=" + encodedAppDisplayName
            } else {
                qqSchemeURLString += "thirdAppDisplayName=" + "nixApp" // Should not be there
            }
            qqSchemeURLString += "&version=1&cflag=\(type.scene)"
            qqSchemeURLString += "&callback_type=scheme&generalpastboard=1"
            qqSchemeURLString += "&callback_name=\(callbackName)"
            qqSchemeURLString += "&src_type=app&shareType=0&file_type="
            if let media = type.info.media {
                func handleNews(with url: URL, mediaType: String?) {
                    if let thumbnailData = type.info.thumbnail?.monkeyking_compressedImageData {
                        var dic: [String: Any] = ["previewimagedata": thumbnailData]
                        if let oldText = UIPasteboard.general.oldText {
                            dic["pasted_string"] = oldText
                        }
                        let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                        UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    }
                    qqSchemeURLString += mediaType ?? "news"
                    guard let encodedURLString = url.absoluteString.monkeyking_base64AndURLEncodedString else {
                        completionHandler(.failure(.sdk(.urlEncodeFailed)))
                        return
                    }
                    qqSchemeURLString += "&url=\(encodedURLString)"
                }
                switch media {
                case .url(let url):
                    handleNews(with: url, mediaType: "news")
                case .image(let image):
                    guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                        completionHandler(.failure(.resource(.invalidImageData)))
                        return
                    }
                    var dic: [String: Any] = ["file_data": imageData]
                    if let thumbnail = type.info.thumbnail, let thumbnailData = thumbnail.jpegData(compressionQuality: 0.9) {
                        dic["previewimagedata"] = thumbnailData
                    }
                    if let oldText = UIPasteboard.general.oldText {
                        dic["pasted_string"] = oldText
                    }
                    let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                    UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    qqSchemeURLString += "img"
                case .imageData(let data), .gif(let data):
                    var dic: [String: Any] = ["file_data": data]
                    if let thumbnail = type.info.thumbnail, let thumbnailData = thumbnail.jpegData(compressionQuality: 0.9) {
                        dic["previewimagedata"] = thumbnailData
                    }
                    if let oldText = UIPasteboard.general.oldText {
                        dic["pasted_string"] = oldText
                    }
                    let archivedData = NSKeyedArchiver.archivedData(withRootObject: dic)
                    UIPasteboard.general.setData(archivedData, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    qqSchemeURLString += "img"
                case .audio(let audioURL, _):
                    handleNews(with: audioURL, mediaType: "audio")
                case .video(let url):
                    handleNews(with: url, mediaType: nil) // No video type, default is news type.
                case .file(let fileData, _):
                    var dic: [String: Any] = ["file_data": fileData]
                    if let oldText = UIPasteboard.general.oldText {
                        dic["pasted_string"] = oldText
                    }
                    let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                    UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    qqSchemeURLString += "localFile"
                    if let filename = type.info.description?.monkeyking_urlEncodedString {
                        qqSchemeURLString += "&fileName=\(filename)"
                    }
                case .miniApp:
                    fatalError("QQ not supports Mini App type")
                }
                if let encodedTitle = type.info.title?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "&title=\(encodedTitle)"
                }
                if let encodedDescription = type.info.description?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "&objectlocation=pasteboard&description=\(encodedDescription)"
                }
                qqSchemeURLString += "&sdkv=2.9"

            } else { // Share Text
                // fix #75
                switch type {
                case .zone:
                    qqSchemeURLString += "qzone&title="
                default:
                    qqSchemeURLString += "text&file_data="
                }
                if let encodedDescription = type.info.description?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "\(encodedDescription)"
                }
            }
            openURL(urlString: qqSchemeURLString) { flag in
                if flag { return }
                completionHandler(.failure(.sdk(.invalidURLScheme)))
            }
        case .weibo(let type):
            guard !shared.canOpenURL(urlString: "weibosdk://request") else {
                // App Share
                var messageInfo: [String: Any] = [
                    "__class": "WBMessageObject",
                ]
                let info = type.info
                if let description = info.description {
                    messageInfo["text"] = description
                }
                if let media = info.media {
                    switch media {
                    case .url(let url):
                        if let thumbnailData = info.thumbnail?.monkeyking_compressedImageData {
                            var mediaObject: [String: Any] = [
                                "__class": "WBWebpageObject",
                                "objectID": "identifier1",
                            ]
                            mediaObject["webpageUrl"] = url.absoluteString
                            mediaObject["title"] = info.title ?? ""
                            mediaObject["thumbnailData"] = thumbnailData
                            messageInfo["mediaObject"] = mediaObject
                        } else {
                            // Deliver text directly.
                            let text = info.description ?? ""
                            messageInfo["text"] = text.isEmpty ? url.absoluteString : text + " " + url.absoluteString
                        }
                    case .image(let image):
                        if let imageData = image.jpegData(compressionQuality: 0.9) {
                            messageInfo["imageObject"] = ["imageData": imageData]
                        }
                    case .imageData(let imageData):
                        messageInfo["imageObject"] = ["imageData": imageData]
                    case .gif:
                        fatalError("Weibo not supports GIF type")
                    case .audio:
                        fatalError("Weibo not supports Audio type")
                    case .video:
                        fatalError("Weibo not supports Video type")
                    case .file:
                        fatalError("Weibo not supports File type")
                    case .miniApp:
                        fatalError("Weibo not supports Mini App type")
                    }
                }
                let uuidString = UUID().uuidString
                let dict: [String: Any] = [
                    "__class": "WBSendMessageToWeiboRequest",
                    "message": messageInfo,
                    "requestID": uuidString,
                ]
                let appData = NSKeyedArchiver.archivedData(
                    withRootObject: [
                        "appKey": appID,
                        "bundleID": Bundle.main.monkeyking_bundleID ?? "",
                    ]
                )
                let messageData: [[String: Any]] = [
                    ["transferObject": NSKeyedArchiver.archivedData(withRootObject: dict)],
                    ["app": appData],
                ]
                UIPasteboard.general.items = messageData
                openURL(urlString: "weibosdk://request?id=\(uuidString)&sdkversion=003013000") { flag in
                    if flag { return }
                    completionHandler(.failure(.sdk(.invalidURLScheme)))
                }
                return
            }
            // Weibo Web Share
            let info = type.info
            var parameters = [String: Any]()
            guard let accessToken = type.accessToken else {
                completionHandler(.failure(.noAccount))
                return
            }
            parameters["access_token"] = accessToken
            var status: [String?] = [info.title, info.description]
            var mediaType = Media.url(NSURL() as URL)
            if let media = info.media {
                switch media {
                case .url(let url):
                    status.append(url.absoluteString)
                    mediaType = Media.url(url)
                case .image(let image):
                    guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                        completionHandler(.failure(.resource(.invalidImageData)))
                        return
                    }
                    parameters["pic"] = imageData
                    mediaType = Media.image(image)
                case .imageData(let imageData):
                    parameters["pic"] = imageData
                    mediaType = Media.imageData(imageData)
                case .gif:
                    fatalError("web Weibo not supports GIF type")
                case .audio:
                    fatalError("web Weibo not supports Audio type")
                case .video:
                    fatalError("web Weibo not supports Video type")
                case .file:
                    fatalError("web Weibo not supports File type")
                case .miniApp:
                    fatalError("web Weibo not supports Mini App type")
                }
            }
            let statusText = status.compactMap { $0 }.joined(separator: " ")
            parameters["status"] = statusText
            switch mediaType {
            case .url:
                let urlString = "https://api.weibo.com/2/statuses/share.json"
                shared.request(urlString, method: .post, parameters: parameters) { responseData, _, error in
                    if error != nil {
                        completionHandler(.failure(.apiRequest(.connectFailed)))
                    } else if let responseData = responseData, (responseData["idstr"] as? String) == nil {
                        completionHandler(.failure(shared.errorReason(with: responseData, at: .weibo)))
                    } else {
                        completionHandler(.success(nil))
                    }
                }
            case .image, .imageData:
                let urlString = "https://api.weibo.com/2/statuses/share.json"
                shared.upload(urlString, parameters: parameters) { responseData, _, error in
                    if error != nil {
                        completionHandler(.failure(.apiRequest(.connectFailed)))
                    } else if let responseData = responseData, (responseData["idstr"] as? String) == nil {
                        completionHandler(.failure(shared.errorReason(with: responseData, at: .weibo)))
                    } else {
                        completionHandler(.success(nil))
                    }
                }
            case .gif:
                fatalError("web Weibo not supports GIF type")
            case .audio:
                fatalError("web Weibo not supports Audio type")
            case .video:
                fatalError("web Weibo not supports Video type")
            case .file:
                fatalError("web Weibo not supports File type")
            case .miniApp:
                fatalError("web Weibo not supports Mini App type")
            }
        case .alipay(let type):
            let dictionary = createAlipayMessageDictionary(withScene: type.scene, info: type.info, appID: appID)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: .init()) else {
                completionHandler(.failure(.sdk(.serializeFailed)))
                return
            }
            UIPasteboard.general.setData(data, forPasteboardType: "com.alipay.openapi.pb.req.\(appID)")
            openURL(urlString: "alipayshare://platformapi/shareService?action=sendReq&shareId=\(appID)") { flag in
                if flag { return }
                completionHandler(.failure(.sdk(.invalidURLScheme)))
            }
        case .twitter(let type):
            // MARK: - Twitter Deliver
            guard let accessToken = type.accessToken,
                let accessTokenSecret = type.accessTokenSecret,
                let account = shared.accountSet[.twitter] else {
                completionHandler(.failure(.noAccount))
                return
            }
            let info = type.info
            var status = [info.title, info.description]
            var parameters = [String: Any]()
            var mediaType = Media.url(NSURL() as URL)
            if let media = info.media {
                switch media {
                case .url(let url):
                    status.append(url.absoluteString)
                    mediaType = Media.url(url)
                case .image(let image):
                    guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                        completionHandler(.failure(.resource(.invalidImageData)))
                        return
                    }
                    parameters["media"] = imageData
                    mediaType = Media.image(image)
                case .imageData(let imageData):
                    parameters["media"] = imageData
                    mediaType = Media.imageData(imageData)
                default:
                    fatalError("web Twitter not supports this type")
                }
            }
            switch mediaType {
            case .url:
                let statusText = status.compactMap { $0 }.joined(separator: " ")
                let updateStatusAPI = "https://api.twitter.com/1.1/statuses/update.json"
                var parameters = ["status": statusText]
                if let mediaIDs = type.mediaIDs {
                    parameters["media_ids"] = mediaIDs.joined(separator: ",")
                }
                if case .twitter(let appID, let appKey, _) = account {
                    let oauthString = Networking.shared.authorizationHeader(for: .post, urlString: updateStatusAPI, appID: appID, appKey: appKey, accessToken: accessToken, accessTokenSecret: accessTokenSecret, parameters: parameters, isMediaUpload: true)
                    let headers = ["Authorization": oauthString]
                    // ref: https://dev.twitter.com/rest/reference/post/statuses/update
                    let urlString = "\(updateStatusAPI)?\(parameters.urlEncodedQueryString(using: .utf8))"
                    shared.request(urlString, method: .post, parameters: nil, headers: headers) { responseData, URLResponse, error in
                        if error != nil {
                            completionHandler(.failure(.apiRequest(.connectFailed)))
                        } else {
                            if let HTTPResponse = URLResponse as? HTTPURLResponse,
                                HTTPResponse.statusCode == 200 {
                                completionHandler(.success(nil))
                                return
                            }
                            if let responseData = responseData,
                                let _ = responseData["errors"] {
                                completionHandler(.failure(shared.errorReason(with: responseData, at: .twitter)))
                                return
                            }
                            completionHandler(.failure(.apiRequest(.unrecognizedError(response: responseData))))
                        }
                    }
                }
            case .image, .imageData:
                let uploadMediaAPI = "https://upload.twitter.com/1.1/media/upload.json"
                if case .twitter(let appID, let appKey, _) = account {
                    // ref: https://dev.twitter.com/rest/media/uploading-media#keepinmind
                    let oauthString = Networking.shared.authorizationHeader(for: .post, urlString: uploadMediaAPI, appID: appID, appKey: appKey, accessToken: accessToken, accessTokenSecret: accessTokenSecret, parameters: nil, isMediaUpload: false)
                    let headers = ["Authorization": oauthString]
                    shared.upload(uploadMediaAPI, parameters: parameters, headers: headers) { responseData, URLResponse, error in
                        if let statusCode = (URLResponse as? HTTPURLResponse)?.statusCode,
                            statusCode == 200 {
                            completionHandler(.success(responseData))
                            return
                        }
                        if error != nil {
                            completionHandler(.failure(.apiRequest(.connectFailed)))
                        } else {
                            completionHandler(.failure(.apiRequest(.unrecognizedError(response: responseData))))
                        }
                    }
                }
            default:
                fatalError("web Twitter not supports this mediaType")
            }
        }
    }
}

// MARK: Pay

extension MonkeyKing {

    public enum Order {
        /// You can custom URL scheme. Default "ap" + String(appID)
        /// ref: https://doc.open.alipay.com/docs/doc.htm?spm=a219a.7629140.0.0.piSRlm&treeId=204&articleId=105295&docType=1
        case alipay(urlString: String)
        case weChat(urlString: String)

        public var canBeDelivered: Bool {
            let scheme: String
            switch self {
            case .alipay:
                scheme = "alipay://"
            case .weChat:
                scheme = "weixin://"
            }
            return shared.canOpenURL(urlString: scheme)
        }
    }

    public class func deliver(_ order: Order, completionHandler: @escaping PayCompletionHandler) {
        if !order.canBeDelivered {
            completionHandler(.failure(.noApp))
            return
        }
        shared.payCompletionHandler = completionHandler
        shared.oauthCompletionHandler = nil
        shared.deliverCompletionHandler = nil
        shared.openSchemeCompletionHandler = nil

        switch order {
        case .weChat(let urlString):
            openURL(urlString: urlString) { flag in
                if flag { return }
                completionHandler(.failure(.apiRequest(.unrecognizedError(response: nil))))
            }
        case .alipay(let urlString):
            openURL(urlString: urlString) { flag in
                if flag { return }
                completionHandler(.failure(.apiRequest(.unrecognizedError(response: nil))))
            }
        }
    }
}

// MARK: OAuth

extension MonkeyKing {

    public class func oauth(for platform: SupportedPlatform, scope: String? = nil, requestToken: String? = nil, dataString: String? = nil, completionHandler: @escaping OAuthCompletionHandler) {

        guard let account = shared.accountSet[platform] else {
            completionHandler(.failure(.noAccount))
            return
        }

        guard account.isAppInstalled || account.canWebOAuth else {
            completionHandler(.failure(.noApp))
            return
        }

        shared.oauthCompletionHandler = completionHandler
        shared.payCompletionHandler = nil
        shared.deliverCompletionHandler = nil
        shared.openSchemeCompletionHandler = nil

        switch account {
        case .alipay(let appID):

            guard let dataStr = dataString else {
                completionHandler(.failure(.apiRequest(.missingParameter)))
                return
            }

            let appUrlScheme = "apoauth" + appID
            let resultDic: [String: String] = ["fromAppUrlScheme": appUrlScheme, "requestType": "SafePay", "dataString": dataStr]

            guard var resultStr = resultDic.toString else {
                completionHandler(.failure(.sdk(.urlEncodeFailed)))
                return
            }

            resultStr = resultStr.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
            resultStr = resultStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resultStr
            resultStr = "alipay://alipayclient/?" + resultStr

            openURL(urlString: resultStr) { flag in
                if flag { return }
                completionHandler(.failure(.userCancelled))
            }

        case .weChat(let appID, _, _):
            let scope = scope ?? "snsapi_userinfo"
            if !account.isAppInstalled {
                // SMS OAuth
                // uid??
                let accessTokenAPI = "https://open.weixin.qq.com/connect/mobilecheck?appid=\(appID)&uid=1926559385"
                addWebView(withURLString: accessTokenAPI)
            } else {
                openURL(urlString: "weixin://app/\(appID)/auth/?scope=\(scope)&state=Weixinauth") { flag in
                    if flag { return }
                    completionHandler(.failure(.userCancelled))
                }
            }
        case .qq(let appID):
            let scope = scope ?? ""
            guard !account.isAppInstalled else {
                let appName = Bundle.main.monkeyking_displayName ?? "nixApp"
                let dic = [
                    "app_id": appID,
                    "app_name": appName,
                    "client_id": appID,
                    "response_type": "token",
                    "scope": scope,
                    "sdkp": "i",
                    "sdkv": "2.9",
                    "status_machine": UIDevice.current.model,
                    "status_os": UIDevice.current.systemVersion,
                    "status_version": UIDevice.current.systemVersion,
                ]
                let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.tencent\(appID)")
                openURL(urlString: "mqqOpensdkSSoLogin://SSoLogin/tencent\(appID)/com.tencent.tencent\(appID)?generalpastboard=1") { flag in
                    if flag { return }
                    completionHandler(.failure(.userCancelled))
                }
                return
            }
            // Web OAuth
            let accessTokenAPI = "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?appid=716027609&pt_3rd_aid=209656&style=35&s_url=http%3A%2F%2Fconnect.qq.com&refer_cgi=m_authorize&client_id=\(appID)&redirect_uri=auth%3A%2F%2Fwww.qq.com&response_type=token&scope=\(scope)"
            addWebView(withURLString: accessTokenAPI)
        case .weibo(let appID, _, let redirectURL):
            let scope = scope ?? "all"
            guard !account.isAppInstalled else {
                let uuidString = UUID().uuidString
                let transferObjectData = NSKeyedArchiver.archivedData(
                    withRootObject: [
                        "__class": "WBAuthorizeRequest",
                        "redirectURI": redirectURL,
                        "requestID": uuidString,
                        "scope": scope,
                    ]
                )
                let userInfoData = NSKeyedArchiver.archivedData(
                    withRootObject: [
                        "mykey": "as you like",
                        "SSO_From": "SendMessageToWeiboViewController",
                    ]
                )
                let appData = NSKeyedArchiver.archivedData(
                    withRootObject: [
                        "appKey": appID,
                        "bundleID": Bundle.main.monkeyking_bundleID ?? "",
                        "name": Bundle.main.monkeyking_displayName ?? "",
                    ]
                )
                let authItems: [[String: Any]] = [
                    ["transferObject": transferObjectData],
                    ["userInfo": userInfoData],
                    ["app": appData],
                ]
                UIPasteboard.general.items = authItems
                openURL(urlString: "weibosdk://request?id=\(uuidString)&sdkversion=003013000") { flag in
                    if flag { return }
                    completionHandler(.failure(.userCancelled))
                }
                return
            }
            // Web OAuth
            let accessTokenAPI = "https://api.weibo.com/oauth2/authorize?client_id=\(appID)&response_type=code&redirect_uri=\(redirectURL)&scope=\(scope)"
            addWebView(withURLString: accessTokenAPI)
        case .pocket(let appID):
            guard let startIndex = appID.range(of: "-")?.lowerBound else {
                return
            }
            let prefix = appID[..<startIndex]
            let redirectURLString = "pocketapp\(prefix):authorizationFinished"
            guard let requestToken = requestToken else { return }
            guard !account.isAppInstalled else {
                let requestTokenAPI = "pocket-oauth-v1:///authorize?request_token=\(requestToken)&redirect_uri=\(redirectURLString)"
                openURL(urlString: requestTokenAPI) { flag in
                    if flag { return }
                    completionHandler(.failure(.userCancelled))
                }
                return
            }
            let requestTokenAPI = "https://getpocket.com/auth/authorize?request_token=\(requestToken)&redirect_uri=\(redirectURLString)"
            DispatchQueue.main.async {
                addWebView(withURLString: requestTokenAPI)
            }
        case .twitter(let appID, let appKey, let redirectURL):
            shared.twitterAuthenticate(appID: appID, appKey: appKey, redirectURL: redirectURL)
        }
    }

    public class func weChatOAuthForCode(scope: String? = nil, requestToken: String? = nil, completionHandler: @escaping OAuthFromWeChatCodeCompletionHandler) {
        guard let account = shared.accountSet[.weChat] else { return }
        guard account.isAppInstalled || account.canWebOAuth else {
            completionHandler(.failure(.noApp))
            return
        }
        shared.oauthFromWeChatCodeCompletionHandler = completionHandler
        switch account {
        case .weChat(let appID, _, _):
            let scope = scope ?? "snsapi_userinfo"
            guard account.isAppInstalled else {
                completionHandler(.failure(.noApp))
                return
            }
            openURL(urlString: "weixin://app/\(appID)/auth/?scope=\(scope)&state=Weixinauth") { flag in
                if flag { return }
                completionHandler(.failure(.noApp))
            }
        default:
            break
        }
    }

    // Twitter Authenticate
    // https://dev.twitter.com/web/sign-in/implementing
    private func twitterAuthenticate(appID: String, appKey: String, redirectURL: String) {
        let requestTokenAPI = "https://api.twitter.com/oauth/request_token"
        let oauthString = Networking.shared.authorizationHeader(for: .post, urlString: requestTokenAPI, appID: appID, appKey: appKey, accessToken: nil, accessTokenSecret: nil, parameters: ["oauth_callback": redirectURL], isMediaUpload: false)
        let oauthHeader = ["Authorization": oauthString]
        Networking.shared.request(requestTokenAPI, method: .post, parameters: nil, encoding: .url, headers: oauthHeader) { responseData, _, _ in
            if let responseData = responseData,
                let requestToken = (responseData["oauth_token"] as? String) {
                let loginURL = "https://api.twitter.com/oauth/authenticate?oauth_token=\(requestToken)"
                MonkeyKing.addWebView(withURLString: loginURL)
            }
        }
    }
}

extension MonkeyKing {

    public enum Program {
        public enum WeChatSubType {
            case miniApp(username: String, path: String?, type: MiniAppType)
        }

        case weChat(WeChatSubType)
    }

    public class func launch(_ program: Program, completionHandler: @escaping LaunchCompletionHandler) {
        guard let account = shared.accountSet[.weChat] else {
            completionHandler(.failure(.noAccount))
            return
        }

        shared.launchCompletionHandler = completionHandler

        switch program {
        case .weChat(let type):
            switch type {
            case .miniApp(let username, let path, let type):
                var components = URLComponents(string: "weixin://app/\(account.appID)/jumpWxa/")
                components?.queryItems = [
                    URLQueryItem(name: "userName", value: username),
                    URLQueryItem(name: "path", value: path),
                    URLQueryItem(name: "miniProgramType", value: String(type.rawValue)),
                ]
                guard let urlString = components?.url?.absoluteString else {
                    completionHandler(.failure(.sdk(.invalidURLScheme)))
                    return
                }
                openURL(urlString: urlString) { flag in
                    if flag { return }
                    completionHandler(.failure(.sdk(.invalidURLScheme)))
                }
            }
        }
    }
}

// MARK: Open URL

extension MonkeyKing {

    public class func openScheme(_ scheme: String, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:], completionHandler: OpenSchemeCompletionHandler? = nil) {

        shared.openSchemeCompletionHandler = completionHandler
        shared.deliverCompletionHandler = nil
        shared.payCompletionHandler = nil
        shared.oauthCompletionHandler = nil

        let handleErrorResult: () -> Void = {
            shared.openSchemeCompletionHandler = nil
            completionHandler?(.failure(.apiRequest(.unrecognizedError(response: nil))))
        }

        if let url = URL(string: scheme) {
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url, options: options) { flag in
                    if !flag {
                        handleErrorResult()
                    }
                }
            } else {
                let resutl = UIApplication.shared.openURL(url)
                if !resutl {
                    handleErrorResult()
                }
            }
        } else {
            handleErrorResult()
        }
    }
}
