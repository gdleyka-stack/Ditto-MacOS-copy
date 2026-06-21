import SwiftUI
import AppKit
import Combine

// Supported clipboard item types
enum ClipboardType: String, Codable {
    case text
    case image
}

// Model for clipboard items
struct ClipboardItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let type: ClipboardType
    let text: String?
    let imagePath: String?
    let timestamp: Date
    var isPinned: Bool? // Optional for backwards compatibility
}

// Extension to convert NSImage to PNG data
extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

// Helper class to monitor and intercept keyboard events locally
class KeyMonitor {
    private var monitor: Any?

    func start(onKeyDown: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if onKeyDown(event) {
                return nil // Event handled, do not propagate
            }
            return event
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// Clipboard Monitor Service
class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var changeCount = NSPasteboard.general.changeCount
    private var timer: AnyCancellable?
    
    private var appSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Ditto")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        return appSupportDir
    }
    
    private var saveURL: URL {
        return appSupportURL.appendingPathComponent("history.json")
    }
    
    private var imagesURL: URL {
        let dir = appSupportURL.appendingPathComponent("Images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        loadHistory()
        startMonitoring()
    }

    func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
            }
    }

    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        // 1. Try reading text
        if let newText = pasteboard.string(forType: .string) {
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if items.first?.type == .text && items.first?.text == trimmed { return }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                self.items.insert(ClipboardItem(type: .text, text: trimmed, imagePath: nil, timestamp: Date(), isPinned: false), at: 0)
                pruneHistory()
            }
            saveHistory()
            return
        }
        
        // 2. Try reading image
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if let availableType = pasteboard.availableType(from: imageTypes),
           let data = pasteboard.data(forType: availableType) {
            
            let filename = "\(UUID().uuidString).png"
            let fileURL = imagesURL.appendingPathComponent(filename)
            
            let finalData: Data
            if availableType == .tiff, let tiffImage = NSImage(data: data), let pngData = tiffImage.pngData {
                finalData = pngData
            } else {
                finalData = data
            }
            
            do {
                try finalData.write(to: fileURL)
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.items.insert(ClipboardItem(type: .image, text: nil, imagePath: filename, timestamp: Date(), isPinned: false), at: 0)
                    pruneHistory()
                }
                saveHistory()
            } catch {
                print("Failed to save image copy: \(error)")
            }
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == .text, let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if item.type == .image, let filename = item.imagePath {
            let fileURL = imagesURL.appendingPathComponent(filename)
            if let image = NSImage(contentsOf: fileURL) {
                pasteboard.writeObjects([image])
            }
        }
        
        self.changeCount = pasteboard.changeCount
    }

    func deleteItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(of: item) {
            if item.type == .image, let filename = item.imagePath {
                let fileURL = imagesURL.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                items.remove(at: index)
            }
            saveHistory()
        }
    }
    
    func togglePin(for item: ClipboardItem) {
        if let index = items.firstIndex(of: item) {
            items[index].isPinned = !(items[index].isPinned ?? false)
            saveHistory()
        }
    }

    func clearAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            let unpinned = items.filter { !($0.isPinned ?? false) }
            for item in unpinned {
                if item.type == .image, let filename = item.imagePath {
                    let fileURL = imagesURL.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            items = items.filter { $0.isPinned ?? false }
        }
        saveHistory()
    }
    
    private func pruneHistory() {
        while items.count > 50 {
            if let oldestUnpinnedIndex = items.enumerated()
                .filter({ !($0.element.isPinned ?? false) })
                .map({ $0.offset })
                .last {
                
                let itemToRemove = items[oldestUnpinnedIndex]
                if itemToRemove.type == .image, let filename = itemToRemove.imagePath {
                    let fileURL = imagesURL.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                items.remove(at: oldestUnpinnedIndex)
            } else {
                break // Stop pruning if all items are pinned
            }
        }
    }
    
    func imageURL(for filename: String) -> URL {
        return imagesURL.appendingPathComponent(filename)
    }
    
    private func loadHistory() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        self.items = decoded
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: saveURL)
        }
    }
}

// Translucent backing view for window glassmorphism
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Individual cell representing a copied item
struct ClipboardItemCell: View {
    let item: ClipboardItem
    let imageURL: URL?
    let isSelected: Bool
    let onHoverChanged: (Bool) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    @State private var isHovered = false
    @State private var isCopyHovered = false
    @State private var isDeleteHovered = false
    @State private var isPinHovered = false
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: item.timestamp)
    }

    var body: some View {
        HStack(spacing: 12) {
            if item.type == .image, let url = imageURL, let nsImage = NSImage(contentsOfFile: url.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                    
                    HStack(spacing: 6) {
                        Text(timeString)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if item.isPinned ?? false {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                        }
                    }
                }
            } else if item.type == .text, let text = item.text {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 6) {
                        Text(timeString)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.8))
                        
                        if item.isPinned ?? false {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text("Image")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(timeString)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            if isHovered || isSelected || (item.isPinned ?? false) {
                HStack(spacing: 10) {
                    Button(action: onTogglePin) {
                        Image(systemName: (item.isPinned ?? false) ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor((item.isPinned ?? false) ? .orange : (isPinHovered ? .primary : .secondary))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPinHovered = h
                        }
                    }
                    .help((item.isPinned ?? false) ? "Unpin" : "Pin")

                    if isHovered || isSelected {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(isCopyHovered ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isCopyHovered = h
                            }
                        }
                        .help("Copy")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(isDeleteHovered ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isDeleteHovered = h
                            }
                        }
                        .help("Delete")
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected || isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
            onHoverChanged(hover)
        }
        .onTapGesture(count: 2) {
            onCopy()
        }
    }
}

enum ClipboardFilter: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    case text = "Text"
    case images = "Images"
}

// Main Clipboard Panel list view
struct ClipboardView: View {
    @ObservedObject var manager: ClipboardManager
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var searchQuery: String = ""
    
    @State private var selectedIndex: Int = 0
    @State private var keyMonitor = KeyMonitor()
    
    var filteredItems: [ClipboardItem] {
        let baseItems: [ClipboardItem]
        switch selectedFilter {
        case .all:
            baseItems = manager.items
        case .favorites:
            baseItems = manager.items.filter { $0.isPinned ?? false }
        case .text:
            baseItems = manager.items.filter { $0.type == .text }
        case .images:
            baseItems = manager.items.filter { $0.type == .image }
        }
        
        if searchQuery.isEmpty {
            return baseItems
        } else {
            return baseItems.filter { item in
                if item.type == .text, let text = item.text {
                    return text.localizedCaseInsensitiveContains(searchQuery)
                }
                return false
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Ditto")
                    .font(.system(.headline, design: .rounded).bold())
                Spacer()
                if !manager.items.isEmpty {
                    Button(action: {
                        manager.clearAll()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear All")
                        }
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
                Text("\(filteredItems.count) items")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search history...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .rounded))
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            // Filter Pills
            HStack(spacing: 6) {
                ForEach(ClipboardFilter.allCases, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFilter = filter
                        }
                    }) {
                        Text(filter.rawValue)
                            .font(.system(.caption, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                            .clipShape(Capsule())
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            
            Divider()
                .opacity(0.2)
            
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: selectedFilter == .images ? "photo" : "doc.on.doc")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No items found")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                let imageUrl = (item.type == .image && item.imagePath != nil) ? manager.imageURL(for: item.imagePath!) : nil
                                ClipboardItemCell(
                                    item: item,
                                    imageURL: imageUrl,
                                    isSelected: selectedIndex == index,
                                    onHoverChanged: { hovered in
                                        if hovered {
                                            selectedIndex = index
                                        }
                                    },
                                    onCopy: {
                                        manager.copyToClipboard(item)
                                        dismissWindow()
                                    },
                                    onDelete: {
                                        manager.deleteItem(item)
                                    },
                                    onTogglePin: {
                                        manager.togglePin(for: item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { newIndex in
                        let count = filteredItems.count
                        if newIndex >= 0 && newIndex < count {
                            let itemId = filteredItems[newIndex].id
                            scrollToItem(id: itemId, proxy: proxy)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: filteredItems) { _ in
            selectedIndex = 0
        }
        .onAppear {
            keyMonitor.start { event in
                handleKeyDown(event)
            }
        }
        .onDisappear {
            keyMonitor.stop()
        }
    }
    
    private func scrollToItem(id: UUID, proxy: ScrollViewProxy) {
        proxy.scrollTo(id)
    }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let itemsCount = filteredItems.count
        guard itemsCount > 0 else { return false }
        
        switch event.keyCode {
        case 125: // Down Arrow
            withAnimation(.easeInOut(duration: 0.1)) {
                selectedIndex = min(selectedIndex + 1, itemsCount - 1)
            }
            return true
            
        case 126: // Up Arrow
            withAnimation(.easeInOut(duration: 0.1)) {
                selectedIndex = max(selectedIndex - 1, 0)
            }
            return true
            
        case 36: // Return
            let item = filteredItems[selectedIndex]
            manager.copyToClipboard(item)
            dismissWindow()
            return true
            
        case 53: // Escape
            dismissWindow()
            return true
            
        default:
            return false
        }
    }
    
    private func dismissWindow() {
        NSApp.keyWindow?.orderOut(nil)
    }
}
