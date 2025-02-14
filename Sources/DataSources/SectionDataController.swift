//
//  SectionDataController.swift
//  DataSources
//
//  Created by muukii on 8/8/17.
//  Copyright © 2017 muukii. All rights reserved.
//

import Foundation

import DifferenceKit

public protocol SectionDataControllerType {
    
    associatedtype ItemType : Differentiable
    associatedtype AdapterType : Updating
    
    func update(items: [ItemType], updateMode: SectionDataController<ItemType, AdapterType>.UpdateMode, immediately: Bool, completion: @escaping () -> Void)
    
    func asSectionDataController() -> SectionDataController<ItemType, AdapterType>
}

/// Type of Model erased SectionDataController
final class AnySectionDataController<A: Updating> {
    
    let source: Any
    
    private let _numberOfItems: () -> Int
    private let _item: (IndexPath) -> Any?
    
    init<T>(source: SectionDataController<T, A>) {
        self.source = source
        _numberOfItems = {
            source.numberOfItems()
        }
        _item = {
            guard let index = source.toIndex(from: $0) else { return nil }
            return source.snapshot[index]
        }
    }
    
    public func numberOfItems() -> Int {
        return _numberOfItems()
    }
    
    public func item(for indexPath: IndexPath) -> Any? {
        return _item(indexPath)
    }
    
    func restore<T>(itemType: T.Type) -> SectionDataController<T, A> {
        guard let r = source as? SectionDataController<T, A> else {
            fatalError("itemType is different to SectionDataSource.ItemType")
        }
        return r
    }
}

/// DataSource for a section
public final class SectionDataController<T: Differentiable, A: Updating>: SectionDataControllerType {
    
    public typealias ItemType = T
    public typealias AdapterType = A
    
    public enum State {
        case idle
        case updating
    }
    
    public enum UpdateMode {
        case everything
        case partial(animated: Bool)
    }
    
    // MARK: - Properties
    
    private(set) public var items: [T] = []
    
    private(set) public var snapshot: [T] = []
    
    private var work: DispatchWorkItem? = nil
    
    private var state: State = .idle
    
    private let adapter: AdapterType
    
    public internal(set) var displayingSection: Int
    
    // MARK: - Initializers
    
    /// Initialize
    ///
    /// - Parameters:
    ///   - itemType:
    ///   - adapter:
    ///   - displayingSection:
    ///   - isEqual: To use for decision that item should update.
    public init(itemType: ItemType.Type? = nil, adapter: AdapterType, displayingSection: Int = 0) {
        self.adapter = adapter
        self.displayingSection = displayingSection
    }
    
    // MARK: - Functions
    
    /// Return number of items based on snapshot
    ///
    /// - Returns:
    public func numberOfItems() -> Int {
        return snapshot.count
    }
    
    /// Return item based on snapshot
    ///
    /// - Returns:
    public func item(at indexPath: IndexPath) -> T? {
        guard let index = toIndex(from: indexPath) else { return nil }
        guard snapshot.indices.contains(index) else { return nil }
        return snapshot[index]
    }
    
    /// Reserves that a move occurred in DataSource by View operation.
    ///
    /// If you moved item on View, operation following order,
    /// 1. Call reserveMoved(...
    /// 2. Reorder items
    /// 3. update(items: [T]..
    ///
    /// - Parameters:
    ///   - sourceIndexPath:
    ///   - destinationIndexPath:
    public func reserveMoved(source sourceIndexPath: IndexPath, destination destinationIndexPath: IndexPath) {
        
        precondition(
            sourceIndexPath.section == displayingSection,
            "sourceIndexPath.section \(sourceIndexPath.section) must be equal to \(displayingSection)"
        )
        precondition(
            destinationIndexPath.section == displayingSection,
            "destinationIndexPath.section \(sourceIndexPath.section) must be equal to \(displayingSection)"
        )
        
        let o = snapshot.remove(at: sourceIndexPath.item)
        snapshot.insert(o, at: destinationIndexPath.item)
    }
    
    /// Update
    ///
    /// In default, Calling `update` will be throttled.
    /// If you want to update immediately, set true to `immediately`.
    ///
    /// - Parameters:
    ///   - items:
    ///   - updateMode:
    ///   - immediately: False : indicate to throttled updating
    ///   - completion:
    public func update(
        items: [T],
        updateMode: UpdateMode,
        immediately: Bool = false,
        completion: @escaping () -> Void
    ) {
        
        self.items = items
        
        self.work?.cancel()
        self.work = DispatchWorkItem(block: { [weak self] in
            guard let `self` = self else { return }
            
            let old = self.snapshot
            let new = self.items
            
            self.__update(
                targetSection: self.displayingSection,
                currentDisplayingItems: old,
                newItems: new,
                updateMode: updateMode,
                completion: {
                    completion()
                })
        })
        
        if immediately {
            DispatchQueue.main.async(execute: work!)
        } else {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: work!)
        }
    }
    
    public func asSectionDataController() -> SectionDataController<ItemType, AdapterType> {
        return self
    }
    
    /// Create IndexPath from item and displayingSection.
    ///
    /// - Parameter item:
    /// - Returns:
    public func indexPath(item: Int) -> IndexPath {
        return IndexPath(item: item, section: displayingSection)
    }
    
    @inline(__always)
    fileprivate func toIndex(from indexPath: IndexPath) -> Int? {
        guard indexPath.section == displayingSection else {
            assertionFailure("IndexPath.section (\(indexPath.section)) must be equal to displayingSection (\(displayingSection)).")
            return nil
        }
        return indexPath.item
    }
    
    private func __update(
        targetSection: Int,
        currentDisplayingItems: [T],
        newItems: [T],
        updateMode: UpdateMode,
        completion: @escaping () -> Void
    ) {
        
        assertMainThread()
        
        self.state = .updating
        
        switch updateMode {
        case .everything:
            
            self.snapshot = newItems
            
            adapter.reload {
                assertMainThread()
                self.state = .idle
                completion()
            }
            
        case .partial(let preferredAnimated):
            
            let stagedChangeset = StagedChangeset.init(source: currentDisplayingItems, target: newItems)
            
            let totalChangeCount = stagedChangeset.map { $0.changeCount }.reduce(0, +)
            
            guard totalChangeCount > 0 else {
                self.state = .idle
                completion()
                return
            }
            
            let animated: Bool
            
            if totalChangeCount > 300 {
                animated = false
            } else {
                animated = preferredAnimated
            }
            
            let _adapter = self.adapter
            
            _adapter.performBatch(
                animated: animated,
                updates: {
                    for changeset in stagedChangeset {
                        
                        self.snapshot = changeset.data
                        
                        let updateContext = UpdateContext.init(
                            diff: .init(diff: changeset, targetSection: targetSection),
                            snapshot: changeset.data
                        )
                        
                        if !changeset.elementDeleted.isEmpty {
                            _adapter.deleteItems(at: updateContext.diff.deletes)
                        }
                        
                        if !changeset.elementInserted.isEmpty {
                            _adapter.insertItems(at: updateContext.diff.inserts)
                        }
                        
                        if !changeset.elementUpdated.isEmpty {
                            _adapter.reloadItems(at: updateContext.diff.updates)
                        }
                        
                        for move in updateContext.diff.moves {
                            _adapter.moveItem(
                                at: move.from,
                                to: move.to
                            )
                        }
                    }
                },
                completion: {
                    assertMainThread()
                    self.state = .idle
                    completion()
                }
            )
        }
    }
    
}

extension SectionDataController {
    
    /// IndexPath of Item
    ///
    /// IndexPath will be found by isEqual closure.
    ///
    /// - Parameter item:
    /// - Returns:
    public func indexPath(of item: T) -> IndexPath? {
        guard let index = items.firstIndex(where: { $0.differenceIdentifier == item.differenceIdentifier }) else { return nil }
        return IndexPath(item: index, section: displayingSection)
    }
    
    public func indexPath(of `where`: (T) -> Bool) -> IndexPath? {
        guard let index = items.firstIndex(where:`where`) else { return nil }
        return IndexPath(item: index, section: displayingSection)
    }
}

extension SectionDataController where T : AnyObject {
    
    /// IndexPath of Item
    ///
    /// IndexPath will be found by the pointer for Item.
    ///
    /// - Parameter item:
    /// - Returns:
    public func indexPathPointerPersonality(of item: T) -> IndexPath? {
        guard let index = items.firstIndex(where: { $0 === item }) else { return nil }
        return IndexPath(item: index, section: displayingSection)
    }
}

