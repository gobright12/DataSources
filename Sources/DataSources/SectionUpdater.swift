//
//  Updater.swift
//  DataSources
//
//  Created by muukii on 8/8/17.
//  Copyright © 2017 muukii. All rights reserved.
//

import UIKit

final class SectionUpdater<T: Diffable, A: Updating> {

  enum State {
    case idle
    case updating
  }

  enum UpdateMode {
    case everything
    case partial(animated: Bool, isEqual: EqualityChecker<T>)
  }

  let adapter: A

  private let queue = DispatchQueue.main
  private var state: State = .idle

  init(adapter: A) {
    self.adapter = adapter
  }

  func update(
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
      adapter.reload {
        assertMainThread()
        self.state = .idle
        completion()
      }
    case .partial(let animated, let isEqual):

      let diff = Diff.diffing(
        oldArray: currentDisplayingItems,
        newArray: newItems,
        isEqual: isEqual
      )

      guard diff.changeCount > 0 else {
        completion()
        return
      }

      var animated = animated

      if diff.changeCount > 300 {
        animated = false
      }
      
      let _adapter = self.adapter

      let context = UpdateContext.init(
        newItems: newItems.indices.lazy.map { IndexPath(item: $0, section: targetSection) },
        oldItems: currentDisplayingItems.indices.lazy.map { IndexPath(item: $0, section: targetSection) },
        diff: diff
      )
      
      self.adapter.performBatch(
        in: context,
        animated: animated,
        updates: {
          
          _adapter.reloadItems(at: diff.updates.map { IndexPath(item: $0, section: targetSection) }, in: context)
          _adapter.deleteItems(at: diff.deletes.map { IndexPath(item: $0, section: targetSection) }, in: context)
          _adapter.insertItems(at: diff.inserts.map { IndexPath(item: $0, section: targetSection) }, in: context)
          
          for move in diff.moves {
            _adapter.moveItem(
              at: IndexPath(item: move.from, section: targetSection),
              to: IndexPath(item: move.to, section: targetSection),
              in: context
            )
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
