import Foundation
import Testing
@testable import EnhancerCore

@Test func attemptedAndReturnedImagesRequireExplicitRetryOrSaving() {
    let url = URL(fileURLWithPath: "/tmp/source.png")
    let metadata = ImageMetadata(width: 2400, height: 2400, byteCount: 100, sourceHash: "source", edgeScore: 10, warnings: [])
    var job = EnhancementJob(sourceURL: url, metadata: metadata, isDuplicate: false)
    for status in [JobStatus.preparing, .enhancing, .saving, .completed, .failed, .uncertain, .readyToSave] {
        job.status = status
        #expect(!job.canEnhance)
    }
    job.status = .queued
    #expect(job.canEnhance)
    job.outputURL = URL(fileURLWithPath: "/tmp/enhanced.png")
    #expect(!job.canEnhance)
    job.outputURL = nil
    job.completedAt = Date()
    #expect(!job.canEnhance)
}
