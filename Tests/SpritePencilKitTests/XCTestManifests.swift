import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SpritePencilKitTests.allTests),
    ]
}
#endif
