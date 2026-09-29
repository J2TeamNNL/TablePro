import Darwin
import Foundation
import XCTest

final class HanaHelperPipeTests: XCTestCase {
    func testWritingToAPipeNobodyReadsIsAnErrorAndNotASignal() throws {
        let pipe = Pipe()
        try HanaHelperPipe.suppressBrokenPipeSignal(on: pipe.fileHandleForWriting.fileDescriptor)
        try pipe.fileHandleForReading.close()

        XCTAssertThrowsError(try HanaHelperPipe.write(Data("frame".utf8), to: pipe.fileHandleForWriting.fileDescriptor)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EPIPE)
        }
    }

    func testReadingExactlyWaitsForEveryByte() throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading.fileDescriptor
        let writer = pipe.fileHandleForWriting
        DispatchQueue.global().async {
            for chunk in ["ab", "cd", "e"] {
                try? HanaHelperPipe.write(Data(chunk.utf8), to: writer.fileDescriptor)
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        XCTAssertEqual(try HanaHelperPipe.read(exactly: 5, from: reader), .complete(Data("abcde".utf8)))
        try writer.close()
    }

    func testReadingReportsHowFarTheStreamGotBeforeItEnded() throws {
        let pipe = Pipe()
        try HanaHelperPipe.write(Data("abc".utf8), to: pipe.fileHandleForWriting.fileDescriptor)
        try pipe.fileHandleForWriting.close()
        let reader = pipe.fileHandleForReading.fileDescriptor

        XCTAssertEqual(try HanaHelperPipe.read(exactly: 13, from: reader), .endOfStream(receivedByteCount: 3))
        XCTAssertEqual(try HanaHelperPipe.read(exactly: 13, from: reader), .endOfStream(receivedByteCount: 0))
    }

    func testReadingNothingNeedsNoBytes() throws {
        let pipe = Pipe()

        XCTAssertEqual(try HanaHelperPipe.read(exactly: 0, from: pipe.fileHandleForReading.fileDescriptor), .complete(Data()))
    }
}
