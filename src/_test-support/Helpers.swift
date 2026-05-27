import XCTest

func XCTAssertArraysEqualUnordered<T: Comparable>(
    _ array1: [T],
    _ array2: [T],
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(array1.sorted(), array2.sorted(), message(), file: file, line: line)
}
