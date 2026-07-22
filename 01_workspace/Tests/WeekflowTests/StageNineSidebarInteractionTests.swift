import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageNineSidebarHoverAndSelectionRenderIdentically() throws {
    let selected = SidebarRow(item: .home, selection: .constant(.home))
        .frame(width: 210, height: 32)
        .background(WeekflowPalette.sidebar)
    let hovered = SidebarRow(
        item: .home,
        selection: .constant(.focus),
        forcedHover: true
    )
    .frame(width: 210, height: 32)
    .background(WeekflowPalette.sidebar)
    let normal = SidebarRow(
        item: .home,
        selection: .constant(.focus),
        forcedHover: false
    )
    .frame(width: 210, height: 32)
    .background(WeekflowPalette.sidebar)

    #expect(SidebarRowVisualState.resolve(isSelected: true, isHovering: false) == .highlighted)
    #expect(SidebarRowVisualState.resolve(isSelected: false, isHovering: true) == .highlighted)
    #expect(SidebarRowVisualState.resolve(isSelected: false, isHovering: false) == .normal)

    let comparison = HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
            Text("当前选中").font(.system(size: 10)).foregroundStyle(WeekflowPalette.textMuted)
            selected
        }
        VStack(alignment: .leading, spacing: 5) {
            Text("Hover").font(.system(size: 10)).foregroundStyle(WeekflowPalette.textMuted)
            hovered
        }
        VStack(alignment: .leading, spacing: 5) {
            Text("默认").font(.system(size: 10)).foregroundStyle(WeekflowPalette.textMuted)
            normal
        }
    }
    .padding(16)
    .background(WeekflowPalette.sidebar)
    let comparisonImage = try #require(renderStageNine(comparison))
    try writeStageNineSnapshotIfRequested(comparisonImage, name: "左侧栏-Hover与选中同色-阶段9")
}

@MainActor
private func renderStageNine<V: View>(_ view: V) -> NSImage? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return renderer.nsImage
}

private func stageNinePNGData(_ image: NSImage) throws -> Data {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageNineSnapshotError.encodingFailed
    }
    return png
}

private func writeStageNineSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try stageNinePNGData(image).write(
        to: folder.appendingPathComponent("\(name).png"),
        options: .atomic
    )
}

private enum StageNineSnapshotError: Error {
    case encodingFailed
}
