import Testing
import Foundation
@testable import TransmissionRemote

@Suite("FormatHelpers")
struct FormatHelpersTests {

    // MARK: - formatBytes

    @Test func bytesZero() {
        #expect(formatBytes(0) == "Zero KB")
    }

    @Test func bytesKilobytes() {
        #expect(formatBytes(1_024) == "1 KB")
    }

    @Test func bytesMegabytes() {
        #expect(formatBytes(1_048_576) == "1 MB")
    }

    @Test func bytesGigabytes() {
        #expect(formatBytes(1_000_000_000) == "1 GB")
    }

    // MARK: - formatRate

    @Test func rateZeroReturnsEmpty() {
        #expect(formatRate(0) == "")
    }

    @Test func rateZeroShowZero() {
        #expect(formatRate(0, showZero: true) == "0 KB/s")
    }

    @Test func rateKilobytes() {
        #expect(formatRate(51_200) == "51 KB/s")
    }

    @Test func rateMegabytes() {
        #expect(formatRate(5_242_880) == "5.2 MB/s")
    }

    // MARK: - formatETA

    @Test func etaNegativeReturnsEmpty() {
        #expect(formatETA(-1) == "")
    }

    @Test func etaZeroReturnsEmpty() {
        #expect(formatETA(0) == "")
    }

    @Test func etaSeconds() {
        #expect(formatETA(45) == "45s")
    }

    @Test func etaMinutesAndSeconds() {
        #expect(formatETA(125) == "2m 5s")
    }

    @Test func etaHoursMinutesSeconds() {
        #expect(formatETA(3661) == "1h 1m 1s")
    }

    @Test func etaMultiDay() {
        #expect(formatETA(90000) == "1d 1h")
    }

    // MARK: - formatDuration

    @Test func durationZeroReturnsEmpty() {
        #expect(formatDuration(0) == "")
    }

    @Test func durationNegativeReturnsEmpty() {
        #expect(formatDuration(-10) == "")
    }

    @Test func durationMinutes() {
        #expect(formatDuration(300) == "5m")
    }

    @Test func durationHoursAndMinutes() {
        #expect(formatDuration(3900) == "1h 5m")
    }

    @Test func durationDaysAndHours() {
        #expect(formatDuration(90000) == "1d 1h")
    }

    // MARK: - formatPriority

    @Test func priorityLow() {
        #expect(formatPriority(-1) == "Low")
    }

    @Test func priorityNormal() {
        #expect(formatPriority(0) == "Normal")
    }

    @Test func priorityHigh() {
        #expect(formatPriority(1) == "High")
    }

    @Test func priorityUnknownDefaultsToNormal() {
        #expect(formatPriority(99) == "Normal")
    }

    // MARK: - formatDate / formatRelativeDate

    @Test func dateZeroReturnsEmpty() {
        #expect(formatDate(0) == "")
    }

    @Test func dateNegativeReturnsEmpty() {
        #expect(formatDate(-1) == "")
    }

    @Test func dateValidTimestamp() {
        #expect(!formatDate(1_700_000_000).isEmpty)
    }

    @Test func relativeDateZeroReturnsEmpty() {
        #expect(formatRelativeDate(0) == "")
    }

    @Test func relativeDateValidTimestamp() {
        #expect(!formatRelativeDate(1_700_000_000).isEmpty)
    }

    // MARK: - formatAbsoluteDate

    @Test func absoluteDateZeroReturnsEmpty() {
        #expect(formatAbsoluteDate(0) == "")
    }

    @Test func absoluteDateValidTimestamp() {
        #expect(formatAbsoluteDate(1_700_000_000).contains("2023"))
    }
}
