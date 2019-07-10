import UIKit

class ManageAccountsRouter {
    weak var viewController: UIViewController?
}

extension ManageAccountsRouter: IManageAccountsRouter {

    func showUnlink(accountId: String) {
        viewController?.present(UnlinkRouter.module(accountId: accountId), animated: true)
    }

    func showBackup(account: Account) {
        let module = BackupRouter.module(account: account)
        viewController?.present(module, animated: true)
    }

    func showKey(account: Account) {

    }

    func showRestore(predefinedAccountType: IPredefinedAccountType, delegate: IRestoreAccountTypeDelegate) {
        guard let module = RestoreRouter.module(predefinedAccountType: predefinedAccountType, mode: .presented, delegate: delegate) else {
            return
        }

        viewController?.present(WalletNavigationController(rootViewController: module), animated: true)
    }

    func close() {
        viewController?.dismiss(animated: true)
    }

}

extension ManageAccountsRouter {

    static func module(mode: PresentationMode) -> UIViewController {
        let router = ManageAccountsRouter()
        let interactor = ManageAccountsInteractor(predefinedAccountTypeManager: App.shared.predefinedAccountTypeManager, accountManager: App.shared.accountManager, accountCreator: App.shared.accountCreator)
        let presenter = ManageAccountsPresenter(mode: mode, interactor: interactor, router: router)
        let viewController = ManageAccountsViewController(delegate: presenter)

        interactor.delegate = presenter
        presenter.view = viewController
        router.viewController = viewController

        return viewController
    }

    enum PresentationMode {
        case pushed
        case presented
    }

}
