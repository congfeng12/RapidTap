import Cocoa

/// 更新状态中心
///
/// 主界面（版本更新横幅）与设置面板（软件更新行）共享同一份状态，
/// 避免两处各自发起请求、状态不一致。
final class UpdateManager {

    static let shared = UpdateManager()
    static let stateDidChange = Notification.Name("RapidTapUpdateStateDidChange")

    enum State {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var didAutoCheck = false

    /// 有新版本时返回对应信息
    var availableUpdate: UpdateInfo? {
        if case .available(let info) = self.state {
            return info
        }
        return nil
    }

    /// 是否正在检查或安装
    var isBusy: Bool {
        switch self.state {
        case .checking, .installing:
            return true
        default:
            return false
        }
    }

    private init() {}

    /// 启动后自动检查一次
    func autoCheckIfNeeded() {
        guard !self.didAutoCheck else { return }
        self.didAutoCheck = true
        self.check()
    }

    /// 手动检查
    func check() {
        guard !self.isBusy else { return }
        self.update(.checking)

        UpdateService.shared.check { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let info):
                self.update(info.map { .available($0) } ?? .upToDate)
            case .failure(let error):
                self.update(.failed("检查失败：\(error.localizedDescription)"))
            }
        }
    }

    /// 下载并安装
    func install(_ info: UpdateInfo) {
        guard !self.isBusy else { return }
        self.update(.installing("正在下载 \(info.tag)…"))

        UpdateService.shared.downloadAndInstall(info, progress: { [weak self] message in
            self?.update(.installing(message))
        }, completion: { [weak self] result in
            if case .failure(let error) = result {
                self?.update(.failed("更新失败：\(error.localizedDescription)"))
            }
        })
    }

    private func update(_ state: State) {
        DispatchQueue.main.async {
            self.state = state
            NotificationCenter.default.post(name: UpdateManager.stateDidChange, object: nil)
        }
    }
}
