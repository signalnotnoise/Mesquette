import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// System-managed Apple-hosted pack downloader.
@main
struct AssetDownloader: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool {
        true
    }
}
