//
//  ContentView.swift
//  MacAppIntegration
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import SwiftUI
import AsyncDisplayKit

final class ButtonViewController: ASDKViewController<ASButtonNode> {
    private var tapCount: Int = 0

    override init() {
        let buttonNode = ASButtonNode()
        buttonNode.backgroundColor = NSColor.controlBackgroundColor
        buttonNode.cornerRadius = 10
        buttonNode.contentSpacing = 8
        buttonNode.contentEdgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        buttonNode.imageNode.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Button icon")
        buttonNode.style.preferredSize = CGSize(width: 280, height: 52)

        super.init(node: buttonNode)

        node.addTarget(self, action: #selector(handleButtonTap(_:with:)), forControlEvents: ASControlNodeEvent(rawValue: 1 << 4))
        updateButtonTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateButtonTitle() {
        let title = NSMutableAttributedString(string: "ASButtonNode taps: \(tapCount)")
        title.addAttributes([
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ], range: NSRange(location: 0, length: title.length))
        node.titleNode.attributedText = title
    }

    @objc private func handleButtonTap(_ sender: ASControlNode, with event: Any?) {
        tapCount += 1
        updateButtonTitle()
    }
}

struct ButtonContentView: NSViewControllerRepresentable {
    typealias NSViewControllerType = ButtonViewController

    func makeNSViewController(context: Context) -> ButtonViewController {
        ButtonViewController()
    }

    func updateNSViewController(_ nsViewController: ButtonViewController, context: Context) {
    }
}

final class CollectionCellNode: ASCellNode {
    private let textNode = ASTextNode()

    init(text: String) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = NSColor.controlBackgroundColor
        cornerRadius = 8
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(
            insets: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12),
            child: textNode
        )
    }
}

final class CollectionViewController: ASDKViewController<ASCollectionNode>, ASCollectionDataSource, ASCollectionDelegate {
    private let items = (1...40).map { "Collection row \($0)" }

    override init() {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        let collectionNode = ASCollectionNode(collectionViewLayout: layout)
        super.init(node: collectionNode)
        node.dataSource = self
        node.delegate = self
        node.backgroundColor = NSColor.windowBackgroundColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath) -> ASCellNodeBlock {
        let text = items[indexPath.item]
        return {
            CollectionCellNode(text: text)
        }
    }

    func collectionNode(_ collectionNode: ASCollectionNode, constrainedSizeForItemAt indexPath: IndexPath) -> ASSizeRange {
        let maxWidth = max(200, collectionNode.bounds.width - 24)
        let size = CGSize(width: maxWidth, height: 44)
        return ASSizeRange(min: size, max: size)
    }
}

struct CollectionContentView: NSViewControllerRepresentable {
    typealias NSViewControllerType = CollectionViewController

    func makeNSViewController(context: Context) -> CollectionViewController {
        CollectionViewController()
    }

    func updateNSViewController(_ nsViewController: CollectionViewController, context: Context) {
    }
}
