import Cocoa

/// 一次更新检查的结果
struct UpdateInfo {
    /// 最新版本号，例如 "1.1.0"
    let version: String
    /// 发布标签，例如 "v1.1.0"
    let tag: String
    /// 发布说明（Markdown）
    let notes: String
    /// 发布页地址
    let pageURL: URL
    /// 安装包下载地址
    let assetURL: URL
}

enum UpdateError: LocalizedError {
    case network(String)
    case invalidResponse
    case noCompatibleAsset
    case unpackFailed
    case signatureInvalid
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "网络错误：\(message)"
        case .invalidResponse:
            return "更新信息解析失败"
        case .noCompatibleAsset:
            return "该版本没有可用的安装包"
        case .unpackFailed:
            return "解压安装包失败"
        case .signatureInvalid:
            return "安装包校验失败，已取消更新"
        case .installFailed(let message):
            return "安装失败：\(message)"
        }
    }
}

/// 基于 GitHub Releases 的更新服务
///
/// 访问仓库最新的正式发布（`/releases/latest`，自动排除草稿与预发布），
/// 比较 tag 与当前 `CFBundleShortVersionString`；有新版本时下载 zip、
/// 校验签名与版本号，再替换当前应用并重启。
final class UpdateService {

    static let shared = UpdateService()

    private let repoOwner = "congfeng12"
    private let repoName = "RapidTap"
    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    /// 当前应用版本
    var currentVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 检查更新
    /// - Parameter completion: 有新版本返回 UpdateInfo，已是最新返回 nil；回调在后台线程
    func check(completion: @escaping (Result<UpdateInfo?, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            completion(.failure(UpdateError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RapidTap", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(UpdateError.network(error.localizedDescription)))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(UpdateError.invalidResponse))
                return
            }

            let tag = json["tag_name"] as? String ?? ""
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard !version.isEmpty else {
                completion(.failure(UpdateError.invalidResponse))
                return
            }

            guard UpdateService.isNewer(version, than: self.currentVersion) else {
                completion(.success(nil))
                return
            }

            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let download = assets
                .compactMap({ $0["browser_download_url"] as? String })
                .first(where: { $0.hasSuffix(".zip") }),
                let assetURL = URL(string: download) else {
                completion(.failure(UpdateError.noCompatibleAsset))
                return
            }

            let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? url
            let info = UpdateInfo(version: version,
                                  tag: tag,
                                  notes: json["body"] as? String ?? "",
                                  pageURL: pageURL,
                                  assetURL: assetURL)
            completion(.success(info))
        }.resume()
    }

    /// 下载并安装更新，成功后启动新版本并退出当前进程
    /// - Parameters:
    ///   - info: 检查结果
    ///   - progress: 进度提示（后台线程）
    ///   - completion: 失败时回调错误；成功会直接重启，通常不会返回
    func downloadAndInstall(_ info: UpdateInfo,
                            progress: @escaping (String) -> Void,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        session.downloadTask(with: info.assetURL) { location, _, error in
            if let error = error {
                completion(.failure(UpdateError.network(error.localizedDescription)))
                return
            }
            guard let location = location else {
                completion(.failure(UpdateError.network("下载失败")))
                return
            }

            do {
                try self.install(downloadedFile: location, info: info, progress: progress)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - 安装

    private func install(downloadedFile: URL,
                         info: UpdateInfo,
                         progress: @escaping (String) -> Void) throws {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("RapidTapUpdate-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = workDir.appendingPathComponent("update.zip")
        try fileManager.copyItem(at: downloadedFile, to: zipURL)

        // 解压
        progress("正在解压…")
        let unpackDir = workDir.appendingPathComponent("unpacked")
        try fileManager.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        try UpdateService.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackDir.path])

        guard let newApp = (try? fileManager.contentsOfDirectory(at: unpackDir,
                                                                includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.unpackFailed
        }

        // 校验签名完整性与版本
        progress("正在校验…")
        do {
            try UpdateService.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        } catch {
            throw UpdateError.signatureInvalid
        }

        guard let newBundle = Bundle(url: newApp),
              newBundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let newVersion = newBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              newVersion == info.version else {
            throw UpdateError.signatureInvalid
        }

        // 替换当前应用（先把旧包移走，失败则回滚）
        progress("正在安装…")
        let target = Bundle.main.bundleURL
        let backup = workDir.appendingPathComponent("backup.app")
        try fileManager.moveItem(at: target, to: backup)
        do {
            try fileManager.copyItem(at: newApp, to: target)
        } catch {
            try? fileManager.moveItem(at: backup, to: target)
            throw UpdateError.installFailed(error.localizedDescription)
        }

        try? fileManager.removeItem(at: workDir)

        // 启动新版本并退出
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", target.path]
        try? open.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 工具

    /// 执行外部命令，非 0 退出视为失败
    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw UpdateError.installFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 比较版本号（按点分段，逐段数值比较）
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)

        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}
