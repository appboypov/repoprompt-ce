import Foundation

extension PromptViewModel {
    @MainActor
    private func effectiveCodeMapUsageForChatPromptEntries() -> CodeMapUsage {
        let chatPreset = currentChatPreset()
        let context = resolvedPromptContext(from: chatPreset) ?? resolvePromptContext()
        return context.codeMapUsage
    }

    @MainActor
    func hasPromptSnapshotEntriesForChat() -> Bool {
        let selectionCount = fileManager.selectedFiles.count
        let codeMapUsage = effectiveCodeMapUsageForChatPromptEntries()

        switch codeMapUsage {
        case .none, .selected:
            return selectionCount > 0
        case .auto:
            return selectionCount > 0 || !fileManager.autoCodemapFiles.isEmpty
        case .complete:
            return selectionCount > 0 || !chatCodemapFileAPIs.isEmpty
        }
    }

    @MainActor
    func promptSnapshotEntriesForChatCached() -> [PromptFileEntry] {
        let codeMapUsage = effectiveCodeMapUsageForChatPromptEntries()
        let key = ChatPromptEntriesCacheKey(
            codeMapUsage: codeMapUsage,
            selectionVersion: chatSelectionVersion,
            slicesVersion: chatSlicesVersion,
            autoCodemapVersion: chatAutoCodemapVersion,
            fileAPIsVersion: chatFileAPIsVersion
        )

        if let cache = chatPromptEntriesCache, cache.key == key {
            return cache.entries
        }

        let entries = buildPromptSnapshotEntriesForCurrentChatProjection(codeMapUsage: codeMapUsage)
        chatPromptEntriesCache = (key: key, entries: entries)
        return entries
    }

    @MainActor
    private func buildPromptSnapshotEntriesForCurrentChatProjection(codeMapUsage: CodeMapUsage) -> [PromptFileEntry] {
        let selectedFiles = fileManager.selectedFiles
        let selectedIDs = Set(selectedFiles.map(\.id))
        var entries: [PromptFileEntry] = selectedFiles.map { file in
            PromptFileEntry(
                file: file,
                isCodemap: false,
                ranges: fileManager.selectionSlicesByFileID[file.id]
            )
        }

        for file in fileManager.autoCodemapFiles where !selectedIDs.contains(file.id) {
            entries.append(PromptFileEntry(file: file, isCodemap: true, ranges: nil))
        }

        switch codeMapUsage {
        case .none:
            entries.removeAll { $0.isCodemap }
        case .auto:
            break
        case .selected:
            entries = entries.compactMap { entry in
                guard selectedIDs.contains(entry.file.id) else { return nil }
                let canCodemap = fileManager.validatedFileAPI(for: entry.file) != nil
                return PromptFileEntry(
                    file: entry.file,
                    isCodemap: canCodemap,
                    ranges: canCodemap ? nil : entry.ranges
                )
            }
        case .complete:
            var existingPaths = Set(entries.map(\.file.standardizedFullPath))
            let selectedPaths = Set(selectedFiles.map(\.standardizedFullPath))

            for api in fileManager.validatedCurrentFileAPIs(from: chatCodemapFileAPIs) {
                let standardizedPath = StandardizedPath.absolute(api.filePath)
                guard !selectedPaths.contains(standardizedPath),
                      !existingPaths.contains(standardizedPath),
                      let file = fileManager.findFileByFullPath(standardizedPath)
                else { continue }

                entries.append(PromptFileEntry(file: file, isCodemap: true, ranges: nil))
                existingPaths.insert(standardizedPath)
            }
        }

        return entries
    }

    @MainActor
    func promptSnapshotEntriesForChat() -> [PromptFileEntry] {
        promptSnapshotEntriesForChatCached()
    }
}
