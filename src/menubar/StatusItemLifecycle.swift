import Foundation

/// Main-thread owner. Native status-item effects are injected so lifecycle tests need no menu bar.
final class StatusItemLifecycle<Item: AnyObject> {
    private(set) var item: Item?
    private var stopObserving: (() -> Void)?
    private var generation = UInt64(0)
    private let create: () -> Item
    private let update: (Item) -> Void
    private let observeRemoval: (Item, @escaping () -> Void) -> (() -> Void)
    private let remove: (Item) -> Void
    private let onUserRemoval: () -> Void

    init(create: @escaping () -> Item, update: @escaping (Item) -> Void,
         observeRemoval: @escaping (Item, @escaping () -> Void) -> (() -> Void),
         remove: @escaping (Item) -> Void, onUserRemoval: @escaping () -> Void) {
        self.create = create
        self.update = update
        self.observeRemoval = observeRemoval
        self.remove = remove
        self.onUserRemoval = onUserRemoval
    }

    func setVisible(_ visible: Bool) {
        generation += 1
        guard visible else { removeItem(); return }
        if let item { update(item); return }
        let item = create()
        self.item = item
        update(item)
        stopObserving = observeRemoval(item) { [weak self, weak item] in
            self?.deferUserRemoval(of: item)
        }
    }

    private func removeItem() {
        stopObserving?()
        stopObserving = nil
        guard let item else { return }
        self.item = nil
        remove(item)
    }

    private func deferUserRemoval(of item: Item?) {
        let request = generation
        // Leave AppKit's visibility KVO callback before removing its status item. A newer
        // preference change must win over a queued command-drag removal.
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self, let item, self.item === item, self.generation == request else { return }
            self.setVisible(false)
            self.onUserRemoval()
        }
    }
}
