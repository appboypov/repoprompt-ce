import Foundation

@MainActor
final class AgentFileTagSuggestionService {
    private struct FileCandidate {
        let displayName: String
        let disambiguationLabel: String?
        let commitDisplayText: String
        let matchName: String
        let tokenRelativePath: String
        let scoreRelativePath: String
        let nameLower: String
        let scorePathLower: String
        let standardizedFullPath: String
    }

    private nonisolated static let excludedPathComponent = "_git_data"
    private nonisolated static let fuzzyThreshold: Double = 0.85
    private nonisolated static let indexCandidateMultiplier = 8
    private nonisolated static let minimumIndexCandidateLimit = 64

    private let store: WorkspaceFileContextStore?
    private let searchService: WorkspaceSearchService?
    private weak var selectionCoordinator: WorkspaceSelectionCoordinator?
    private let maxResults: Int

    private var cachedCandidates: [FileCandidate] = []
    private var cachedGenerationSignature: UInt64?
    private var cachedHasMultipleRoots: Bool = false

    init(
        store: WorkspaceFileContextStore?,
        searchService: WorkspaceSearchService?,
        selectionCoordinator: WorkspaceSelectionCoordinator?,
        maxResults: Int = 5
    ) {
        self.store = store
        self.searchService = searchService
        self.selectionCoordinator = selectionCoordinator
        self.maxResults = maxResults
    }

    func suggestions(for rawQuery: String) async -> [MentionSuggestion] {
        guard let store else { return [] }

        let query = RepoSearchQueryFactory.make(rawQuery, supportsWildcards: false)
        if query.isEmpty {
            let selected = await selectedSuggestionsForEmptyQuery(store: store)
            if !selected.isEmpty {
                return Array(selected.prefix(maxResults))
            }
            if !cachedCandidates.isEmpty {
                return Array(cachedCandidates.prefix(maxResults)).map(Self.makeSuggestion(from:))
            }
            return []
        }

        let candidateLimit = max(maxResults * Self.indexCandidateMultiplier, Self.minimumIndexCandidateLimit)
        let catalogResults = await catalogResults(for: query.raw, limit: candidateLimit, store: store)
        let candidates = await makeCandidates(from: catalogResults, store: store)
        guard !candidates.isEmpty else { return [] }
        cachedCandidates = candidates
        cachedGenerationSignature = await store.catalogGeneration(rootScope: .visibleWorkspace)
        cachedHasMultipleRoots = await store.rootRefs(scope: .visibleWorkspace).count > 1
        return scoredSuggestions(from: candidates, query: query)
    }

    private func catalogResults(
        for query: String,
        limit: Int,
        store: WorkspaceFileContextStore
    ) async -> [WorkspaceSearchCatalogEntry] {
        if let searchService {
            let result = await searchService.search(query, limit: limit)
            if result.isIndexReady, !result.isStale {
                let visibleRootIDs = await Set(store.rootRefs(scope: .visibleWorkspace).map(\.id))
                let scopedResults = result.results.filter { visibleRootIDs.contains($0.rootID) }
                return Array(scopedResults.prefix(limit))
            }
        }
        return await storeBackedCatalogResults(for: query, limit: limit, store: store)
    }

    private func storeBackedCatalogResults(
        for query: String,
        limit: Int,
        store: WorkspaceFileContextStore
    ) async -> [WorkspaceSearchCatalogEntry] {
        let snapshot = await store.searchCatalogSnapshot(rootScope: .visibleWorkspace)
        let entries = snapshot.entries
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(entries.prefix(boundedLimit)) }

        let indexedPaths = entries.map { $0.displayPath + "\n" + $0.standardizedFullPath }
        let index = await PathSearchIndex(paths: indexedPaths)
        let hits = await index.search(trimmed, limit: boundedLimit)
        var seenIDs = Set<UUID>()
        var results: [WorkspaceSearchCatalogEntry] = []
        results.reserveCapacity(hits.count)
        for hit in hits where entries.indices.contains(hit.index) {
            let entry = entries[hit.index]
            guard seenIDs.insert(entry.id).inserted else { continue }
            results.append(entry)
        }
        return results
    }

    private func makeCandidates(
        from entries: [WorkspaceSearchCatalogEntry],
        store: WorkspaceFileContextStore
    ) async -> [FileCandidate] {
        let filtered = entries.filter {
            !Self.shouldExcludeFromSuggestions(relativePath: $0.standardizedRelativePath)
        }
        guard !filtered.isEmpty else { return [] }
        let roots = await store.rootRefs(scope: .visibleWorkspace)
        let hasMultipleRoots = roots.count > 1
        let countByFileName = Dictionary(grouping: filtered, by: { $0.name.lowercased() })
            .mapValues(\.count)
        let rootNamesByFileName = Dictionary(grouping: filtered, by: { $0.name.lowercased() })
            .mapValues { Set($0.map { $0.rootName.lowercased() }) }

        var candidates = filtered.map { entry in
            let tokenRelativePath = hasMultipleRoots ? entry.displayPath : entry.standardizedRelativePath
            let scoreRelativePath = entry.standardizedRelativePath
            let fileNameKey = entry.name.lowercased()
            let isDuplicateName = (countByFileName[fileNameKey] ?? 0) > 1
            let spansMultipleRoots = (rootNamesByFileName[fileNameKey]?.count ?? 0) > 1
            let rootLabel = entry.rootName.trimmingCharacters(in: .whitespacesAndNewlines)
            let disambiguationLabel: String? = if isDuplicateName {
                if spansMultipleRoots, !rootLabel.isEmpty {
                    rootLabel
                } else if let parentLabel = Self.parentDirectoryLabel(for: scoreRelativePath), !parentLabel.isEmpty {
                    parentLabel
                } else if !rootLabel.isEmpty {
                    rootLabel
                } else {
                    nil
                }
            } else {
                nil
            }

            return FileCandidate(
                displayName: entry.name,
                disambiguationLabel: disambiguationLabel,
                commitDisplayText: Self.commitDisplayText(
                    fileName: entry.name,
                    tokenRelativePath: tokenRelativePath,
                    isDuplicateName: isDuplicateName
                ),
                matchName: entry.name,
                tokenRelativePath: tokenRelativePath,
                scoreRelativePath: scoreRelativePath,
                nameLower: entry.name.lowercased(),
                scorePathLower: scoreRelativePath.lowercased(),
                standardizedFullPath: entry.standardizedFullPath
            )
        }
        candidates.sort { lhs, rhs in
            if lhs.scorePathLower != rhs.scorePathLower {
                return lhs.scorePathLower < rhs.scorePathLower
            }
            return lhs.tokenRelativePath < rhs.tokenRelativePath
        }
        return candidates
    }

    private func scoredSuggestions(from candidates: [FileCandidate], query: RepoSearchQuery) -> [MentionSuggestion] {
        let scoringCandidates = candidates.map {
            RepoSearchBatchScorer.Candidate(
                name: $0.matchName,
                path: $0.scoreRelativePath,
                nameLower: $0.nameLower,
                pathLower: $0.scorePathLower
            )
        }
        let rawScores = RepoSearchBatchScorer.scores(
            for: scoringCandidates,
            query: query,
            fuzzyThreshold: Self.fuzzyThreshold
        )

        var scored: [(candidate: FileCandidate, score: Int32)] = []
        scored.reserveCapacity(candidates.count)
        for (index, score) in rawScores.enumerated() where score > 0 {
            guard candidates.indices.contains(index) else { continue }
            scored.append((candidates[index], score))
        }

        guard !scored.isEmpty else { return [] }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.candidate.scoreRelativePath.count != rhs.candidate.scoreRelativePath.count {
                return lhs.candidate.scoreRelativePath.count < rhs.candidate.scoreRelativePath.count
            }
            return lhs.candidate.scorePathLower < rhs.candidate.scorePathLower
        }

        return scored
            .prefix(maxResults)
            .map { Self.makeSuggestion(from: $0.candidate) }
    }

    /// Build the suggestion list for a bare `@` from the active stored selection.
    /// This path does not refresh all workspace candidates or materialize UI VMs.
    private func selectedSuggestionsForEmptyQuery(store: WorkspaceFileContextStore) async -> [MentionSuggestion] {
        guard let selectionCoordinator else { return [] }
        let selection = selectionCoordinator.activeSelectionSnapshot(flushPendingUI: true).selection
        guard !selection.selectedPaths.isEmpty else { return [] }
        let visibleRoots = await store.rootRefs(scope: .visibleWorkspace)
        let hasMultipleRoots = visibleRoots.count > 1
        let candidateByPath = makeCandidateByTokenPath()
        var seenIdentities = Set<String>()
        var suggestions: [MentionSuggestion] = []
        suggestions.reserveCapacity(min(maxResults, selection.selectedPaths.count))

        for path in selection.selectedPaths {
            guard let lookup = await store.lookupPath(WorkspacePathLookupRequest(userPath: path, profile: .mcpSelection, rootScope: .visibleWorkspace)),
                  let file = lookup.file else { continue }
            guard !Self.shouldExcludeFromSuggestions(relativePath: file.standardizedRelativePath) else { continue }
            guard seenIdentities.insert(file.standardizedFullPath).inserted else { continue }
            let tokenRelativePath: String = if hasMultipleRoots,
                                               let root = visibleRoots.first(where: { $0.id == file.rootID })
            {
                ClientPathFormatter.displayPath(root: root, relativePath: file.standardizedRelativePath, visibleRoots: visibleRoots)
            } else {
                file.standardizedRelativePath
            }
            if let candidate = candidateByPath[tokenRelativePath] {
                suggestions.append(Self.makeSuggestion(from: candidate))
            } else {
                suggestions.append(MentionSuggestion(
                    displayName: file.name,
                    relativePath: tokenRelativePath,
                    kind: .file,
                    commitDisplayText: file.name
                ))
            }
            if suggestions.count >= maxResults { break }
        }
        return suggestions
    }

    /// Duplicate-tolerant lookup for cached candidates. Keep the first
    /// candidate seen for a given token path so we still pick up any
    /// precomputed disambiguation / display text when we do have a hit.
    private func makeCandidateByTokenPath() -> [String: FileCandidate] {
        Dictionary(
            cachedCandidates.map { ($0.tokenRelativePath, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
    }

    private static func makeSuggestion(from candidate: FileCandidate) -> MentionSuggestion {
        MentionSuggestion(
            displayName: candidate.displayName,
            relativePath: candidate.tokenRelativePath,
            kind: .file,
            subtitle: candidate.disambiguationLabel,
            commitDisplayText: candidate.commitDisplayText
        )
    }

    nonisolated static func commitDisplayText(
        fileName: String,
        tokenRelativePath: String,
        isDuplicateName: Bool
    ) -> String {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isDuplicateName, !trimmedFileName.isEmpty {
            return trimmedFileName
        }
        return tokenRelativePath
    }

    private nonisolated static func shouldExcludeFromSuggestions(relativePath: String) -> Bool {
        relativePath
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .contains { String($0).lowercased() == excludedPathComponent }
    }

    private nonisolated static func parentDirectoryLabel(for relativePath: String) -> String? {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        let parentComponents = components.dropLast()
        guard !parentComponents.isEmpty else { return nil }
        return parentComponents.joined(separator: "/")
    }

    #if DEBUG

        // MARK: - Testing support

        func seedCandidateCacheForTesting(tokenPaths: [String], hasMultipleRoots: Bool) {
            cachedHasMultipleRoots = hasMultipleRoots
            cachedCandidates = tokenPaths.map { tokenPath in
                let basename = (tokenPath as NSString).lastPathComponent
                return FileCandidate(
                    displayName: basename,
                    disambiguationLabel: nil,
                    commitDisplayText: tokenPath,
                    matchName: basename,
                    tokenRelativePath: tokenPath,
                    scoreRelativePath: tokenPath,
                    nameLower: basename.lowercased(),
                    scorePathLower: tokenPath.lowercased(),
                    standardizedFullPath: tokenPath
                )
            }
        }

        var cachedCandidateCountForTesting: Int {
            cachedCandidates.count
        }

        var pathSearchIndexIsBuiltForTesting: Bool {
            false
        }
    #endif
}
