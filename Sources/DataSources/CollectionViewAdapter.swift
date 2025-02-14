//
//  CollectionViewAdapter.swift
//  DataSources
//
//  Created by muukii on 8/8/17.
//  Copyright © 2017 muukii. All rights reserved.
//

import UIKit

open class CollectionViewAdapter: Updating {
    
    public unowned let collectionView: UICollectionView
    
    public var target: UICollectionView {
        return collectionView
    }
    
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
    }
    
    open func insertItems(at indexPaths: [IndexPath]) {
        collectionView.insertItems(at: indexPaths)
    }
    
    open func deleteItems(at indexPaths: [IndexPath]) {
        collectionView.deleteItems(at: indexPaths)
    }
    
    open func reloadItems(at indexPaths: [IndexPath]) {
        collectionView.reloadItems(at: indexPaths)
    }
    
    open func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        collectionView.moveItem(at: indexPath, to: newIndexPath)
    }
    
    open func performBatch(animated: Bool, updates: @escaping () -> Void, completion: @escaping () -> Void) {
        if animated {
            collectionView.performBatchUpdates({
                updates()
            }, completion: { result in
                completion()
            })
        } else {
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            collectionView.performBatchUpdates({
                updates()
            }, completion: { result in
                CATransaction.commit()
                completion()
            })
        }
        
    }
    
    open func reload(completion: @escaping () -> Void) {
        
        collectionView.reloadData()
        completion()
    }
}
