import Foundation
import Photos

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let collectionType: PHAssetCollectionType
    let collectionSubtype: PHAssetCollectionSubtype

    var isSmartAlbum: Bool {
        collectionType == .smartAlbum
    }
}
