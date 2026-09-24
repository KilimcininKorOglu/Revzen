import Testing
@testable import RevzenCore

@Suite("LRUCache")
struct LRUCacheTests {
    @Test("A full cache drops the entry used longest ago, so memory stays bounded")
    func evictsLeastRecentlyUsed() {
        var cache = LRUCache<Int, String>(capacity: 2)
        cache.insert("a", for: 1)
        cache.insert("b", for: 2)
        cache.insert("c", for: 3)
        #expect(cache.count == 2)
        #expect(cache.value(for: 1) == nil)
        #expect(cache.value(for: 3) == "c")
    }

    @Test("Reading an entry keeps it, so a window previewed often keeps its image")
    func readRefreshesEntry() {
        var cache = LRUCache<Int, String>(capacity: 2)
        cache.insert("a", for: 1)
        cache.insert("b", for: 2)
        _ = cache.value(for: 1)
        cache.insert("c", for: 3)
        #expect(cache.value(for: 1) == "a")
        #expect(cache.value(for: 2) == nil)
    }

    @Test("A newer image of the same window replaces the old one without using a second slot")
    func overwriteKeepsOneSlot() {
        var cache = LRUCache<Int, String>(capacity: 2)
        cache.insert("old", for: 1)
        cache.insert("new", for: 1)
        cache.insert("b", for: 2)
        #expect(cache.count == 2)
        #expect(cache.value(for: 1) == "new")
    }

    @Test("A removed entry is gone and frees its slot")
    func removeFreesSlot() {
        var cache = LRUCache<Int, String>(capacity: 2)
        cache.insert("a", for: 1)
        cache.insert("b", for: 2)
        cache.removeValue(for: 1)
        cache.insert("c", for: 3)
        #expect(cache.value(for: 1) == nil)
        #expect(cache.value(for: 2) == "b")
        #expect(cache.count == 2)
    }
}
