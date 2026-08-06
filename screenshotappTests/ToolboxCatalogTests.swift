import Testing
@testable import screenshotapp

struct ToolboxCatalogTests {

    @Test func catalogCoversEveryToolID() {
        for id in ToolboxToolID.allCases {
            #expect(ToolboxCatalog.tool(for: id).id == id)
        }
        #expect(ToolboxCatalog.all.count == ToolboxToolID.allCases.count)
    }

    @Test func derivedKeysMatchRawValuePattern() {
        #expect(ToolboxToolID.dropShelf.enabledKey == "tool.dropShelf.enabled")
        #expect(ToolboxToolID.dropShelf.showInMenuKey == "tool.dropShelf.showInMenu")
        #expect(ToolboxSettings.Keys.captureSelectedAreaEnabled == "tool.captureSelectedArea.enabled")
        #expect(ToolboxSettings.Keys.captureVideoEnabled == "tool.captureVideo.enabled")
    }
}
