//
//  PyTableView.swift
//  Pyto
//
//  Created by Emma Labbé on 18-07-19.
//  Copyright © 2018-2021 Emma Labbé. All rights reserved.
//

import UIKit

@available(iOS 13.0, *) @objc public class PyTableView: PyView, UITableViewDataSource, UITableViewDelegate {
    
    /// The table view associated with this object.
    @objc public var tableView: UITableView! {
        return get {
            return (self.managed as? UITableView) ?? nil
        }
    }
    
    override func releaseHandler() {
        for section in sections {
            (section as? PyTableViewSection)?.tableView = nil
            for cell in (section as? PyTableViewSection)?.cells ?? [] {
                (cell as? PyTableViewCell)?.releaseReference()
            }
                        
            (section as? PyTableViewSection)?.cells = NSArray(array: [])
        }
        
        sections = NSArray(array: [])
        
        DispatchQueue.global().async { [weak self] in
            self?.perform(NSSelectorFromString("release"))
        }
    }
    
    public override class var pythonName: String {
        return "TableView"
    }
    
    @objc private func edit(sender: UIBarButtonItem) {
        
        tableView.setEditing(!tableView.isEditing, animated: true)
        
        if tableView.isEditing {
            sender.title = UIKitLocalizedString(key: "Done")
            sender.style = .done
        } else {
            sender.title = UIKitLocalizedString(key: "Edit")
            sender.style = .plain
        }
    }
    
    private var _editButtonItem: PyButtonItem?
    
    @objc public var editButtonItem: PyButtonItem {
        if let item = _editButtonItem {
            return item
        } else {
            _editButtonItem = PyButtonItem(managed: get {
                return UIBarButtonItem(title: UIKitLocalizedString(key: "Edit"), style: .plain, target: self, action: #selector(self.edit(sender:)))
            })
            return self.editButtonItem
        }
    }
    
    private var swiftySections: [PyTableViewSection] {
        var sections = [PyTableViewSection]()
        
        for section in self.sections {
            if let _section = section as? PyTableViewSection {
                sections.append(_section)
            }
        }
        
        return sections
    }
    
    @objc public var sections = NSArray() {
        didSet {
            set {
                self.tableView?.reloadData()
            }
        }
    }
    
    @objc public func deselectRowAnimated(_ animated: Bool) {
        guard Thread.current.isMainThread else {
            return deselectRowAnimated(animated)
        }
        
        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: indexPath, animated: animated)
        }
    }
    
    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        
        let section = swiftySections[indexPath.section]
        guard let action = section.accessoryButtonTapped else {
            return
        }
        section.call(action: action, for: indexPath.row)
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return swiftySections[section].title
    }
    
    public func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        
        if sourceIndexPath.section != proposedDestinationIndexPath.section {
            var row = 0
            if sourceIndexPath.section < proposedDestinationIndexPath.section {
                row = self.tableView(tableView, numberOfRowsInSection: sourceIndexPath.section) - 1
            }
            return IndexPath(row: row, section: sourceIndexPath.section)
        }
        return proposedDestinationIndexPath
    }
    
    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let section = swiftySections[sourceIndexPath.section]
        guard let action = section.didMoveCell else {
            return
        }
        section.reload = false
        let cells = NSMutableArray(array: section.cells)
        let obj = cells[sourceIndexPath.row]
        cells.removeObject(at: sourceIndexPath.row)
        cells.insert(obj, at: destinationIndexPath.row)
        section.cells = cells
        section.reload = true
        section.call(action: action, for: sourceIndexPath.row, to: destinationIndexPath.row)
    }
    
    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return (swiftySections[indexPath.section].cells[indexPath.row] as? PyTableViewCell)?.movable ?? false
    }
    
    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return (swiftySections[indexPath.section].cells[indexPath.row] as? PyTableViewCell)?.removable ?? false
    }
    
    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        
        guard editingStyle == .delete else {
            return
        }
        
        let section = swiftySections[indexPath.section]
        
        let cells = NSMutableArray(array: section.cells)
        cells.removeObject(at: indexPath.row)
        
        section.reload = false
        section.cells = cells
        section.reload = true
        tableView.deleteRows(at: [indexPath], with: .automatic)
        
        if let action = section.didDeleteCell {
            section.call(action: action, for: indexPath.row)
        }
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = swiftySections[indexPath.section]
        guard let action = section.didSelectCell else {
            return
        }
        section.call(action: action, for: indexPath.row)
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return (swiftySections[indexPath.section].cells[indexPath.row] as? PyTableViewCell)?.cell ?? UITableViewCell()
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return swiftySections.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return swiftySections[section].cells.count
    }
    
    @objc public var reloadAction: PyValue?
    
    @objc public var managedValue: PyValue?
    
    @objc func reload() {
        reloadAction?.call(parameter: managedValue)
        set {
            self.tableView.refreshControl?.endRefreshing()
        }
    }
    
    required init(managed: NSObject! = NSObject()) {
        super.init(managed: managed)
        
        if Thread.current.isMainThread {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(self.reload), for: .valueChanged)
            (managed as? UITableView)?.refreshControl = refreshControl
            (managed as? UITableView)?.dataSource = self
            (managed as? UITableView)?.delegate = self
        } else {
            DispatchQueue.main.async { [weak self] in
                
                guard let self = self else {
                    return
                }
                
                let refreshControl = UIRefreshControl()
                refreshControl.addTarget(self, action: #selector(self.reload), for: .valueChanged)
                (managed as? UITableView)?.refreshControl = refreshControl
                (managed as? UITableView)?.dataSource = self
                (managed as? UITableView)?.delegate = self
            }
        }
    }
    
    @objc class func newView(style: UITableView.Style) -> PyView {
        return PyTableView(managed: get {
            return UITableView(frame: .zero, style: style)
        })
    }
    
    @objc override class func newView() -> PyView {
        return PyTableView(managed: get {
            return UITableView(frame: .zero, style: .plain)
        })
    }
    
    @objc public static let StylePlain = UITableView.Style.plain
    
    @objc public static let StyleGrouped = UITableView.Style.grouped

}
