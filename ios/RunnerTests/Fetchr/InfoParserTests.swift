import XCTest
@testable import Runner

private struct NotSingle: Error {}

private extension Array where Element == FormatOption {
  func qualities() -> [Quality] { map(\.quality) }

  func of(_ quality: Quality) throws -> FormatOption {
    let hits = filter { $0.quality == quality }
    guard hits.count == 1 else { throw NotSingle() }
    return hits[0]
  }
}

final class InfoParserTests: XCTestCase {
  private let url = "https://example.com/watch?v=abc"
  private let tiers: [Quality] = [.best, .p1080, .p720, .p480, .mp3]

  private func parse(_ json: String) throws -> VideoInfo { try InfoParser.parse(json, url: url) }

  private func options(_ formats: String..., duration: String = "100") throws -> [FormatOption] {
    try parse(#"{"_type":"video","duration":\#(duration),"formats":[\#(formats.joined(separator: ","))]}"#).options
  }

  private func video(
    _ width: Int, _ height: Int, vcodec: String = "avc1.4D401F", acodec: String = "none", extra: String = ""
  ) -> String {
    #"{"vcodec":"\#(vcodec)","acodec":"\#(acodec)","width":\#(width),"height":\#(height)\#(extra)}"#
  }

  private func audio(_ acodec: String = "opus", extra: String = "") -> String {
    #"{"vcodec":"none","acodec":"\#(acodec)"\#(extra)}"#
  }

  private func size(_ bytes: Int64) -> String { #","filesize":\#(bytes)"# }

  private func opt(
    _ quality: Quality, _ width: Int64? = nil, _ height: Int64? = nil, _ fps: Double? = nil,
    _ sizeBytes: Int64? = nil, _ estimate: Bool = false
  ) -> FormatOption {
    FormatOption(
      quality: quality, width: width, height: height, fps: fps, sizeBytes: sizeBytes, sizeIsEstimate: estimate)
  }

  private func bare(_ qualities: [Quality]) -> [FormatOption] { qualities.map { opt($0) } }

  func testHdVideoFixtureSumsVideoAndAudioPerTier() throws {
    let info = try parse(infoFixture("video"))

    XCTAssertEqual(url, info.url)
    XCTAssertEqual("Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film", info.title)
    XCTAssertEqual("https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/maxresdefault.webp", info.thumbnail)
    XCTAssertEqual(635, info.durationSeconds)
    XCTAssertEqual("Blender", info.uploader)
    XCTAssertFalse(info.isPlaylist)
    XCTAssertTrue(info.entries.isEmpty)
    XCTAssertEqual(
      [
        opt(.best, 3840, 2160, 60, 712_445_280 + 10_271_496),
        opt(.p1080, 1920, 1080, 60, 257_619_653 + 10_271_496),
        opt(.p720, 1280, 720, 60, 150_524_867 + 10_271_496),
        opt(.p480, 854, 480, 30, 28_207_144 + 10_271_496),
        opt(.mp3, nil, nil, nil, 10_271_496, true),
        opt(.cover, 1920, 1080),
      ],
      info.options)
  }

  func testLowResVideoCollapsesEveryTierIntoBest() throws {
    let info = try parse(infoFixture("video_low_res"))

    XCTAssertEqual("Me at the zoo", info.title)
    XCTAssertEqual(19, info.durationSeconds)
    XCTAssertEqual("jawed", info.uploader)
    XCTAssertEqual(
      [opt(.best, 320, 240, 15, 322_379 + 309_288), opt(.mp3, nil, nil, nil, 309_288, true), opt(.cover)],
      info.options)
  }

  func testAudioOnlyFixtureOffersMp3SizedFromTheBestStreamAndRoundsDuration() throws {
    let info = try parse(infoFixture("audio_only"))

    XCTAssertEqual("Flickermood", info.title)
    XCTAssertEqual("Forss", info.uploader)
    XCTAssertEqual(214, info.durationSeconds)
    XCTAssertEqual("https://i1.sndcdn.com/artworks-000067273316-smsiqx-original.jpg", info.thumbnail)
    XCTAssertEqual([.mp3, .cover], info.options.qualities())
    XCTAssertEqual(4_277_720, try info.options.of(.mp3).sizeBytes)
    XCTAssertTrue(try info.options.of(.mp3).sizeIsEstimate)
    XCTAssertFalse(info.isPlaylist)
  }

  func testVerticalTikTokCapsTheShortSide() throws {
    let info = try parse(infoFixture("tiktok_vertical"))

    XCTAssertEqual(17, info.durationSeconds)
    XCTAssertEqual([.best, .p720, .p480, .mp3, .cover], info.options.qualities())
    XCTAssertEqual(opt(.best, 1080, 1920, nil, 2_889_649), try info.options.of(.best))
    XCTAssertEqual(opt(.p720, 720, 1280, nil, 1_887_507), try info.options.of(.p720))
    XCTAssertEqual(opt(.p480, 576, 1024, nil, 2_593_394), try info.options.of(.p480))
    XCTAssertEqual(opt(.mp3, nil, nil, nil, nil, true), try info.options.of(.mp3))
    XCTAssertEqual(opt(.cover), try info.options.of(.cover))
  }

  func testPlaylistFixtureMapsEntriesAndOffersEveryQualityWithoutMetadata() throws {
    let info = try parse(infoFixture("playlist"))

    XCTAssertTrue(info.isPlaylist)
    XCTAssertEqual("Google - Year In Search (unofficial)", info.title)
    XCTAssertEqual("Google", info.uploader)
    XCTAssertNil(info.durationSeconds)
    XCTAssertTrue(try XCTUnwrap(info.thumbnail).hasSuffix("rs=AOn4CLC_2pbn1Z9xFNrPS46CiimPR3-zRA"))
    XCTAssertEqual(bare(tiers), info.options)
    XCTAssertEqual(3, info.entries.count)

    let first = info.entries[0]
    XCTAssertEqual("https://www.youtube.com/watch?v=KIViy7L_lo8", first.url)
    XCTAssertEqual("2016 — Year in Search", first.title)
    XCTAssertEqual(121, first.durationSeconds)
    XCTAssertTrue(
      try XCTUnwrap(first.thumbnail).hasSuffix("rs=AOn4CLABzVEqTkQPeGIcYHNPL7D31C1p-g"), "last thumbnail wins")
    XCTAssertEqual("El año en búsquedas 2014", info.entries[2].title)
  }

  func testYouTubePlaceholderTitlesAreDroppedButOnlyForYouTube() throws {
    let json = #"""
      {"_type":"playlist","entries":[
        {"ie_key":"Youtube","url":"https://a.test/p","title":"[Private video]"},
        {"ie_key":"Youtube","url":"https://a.test/d","title":"[Deleted video]"},
        {"ie_key":"Youtube","url":"https://a.test/n","title":null},
        {"ie_key":"Youtube","url":"https://a.test/ok","title":"Fine"},
        {"ie_key":"Vimeo","url":"https://a.test/v","title":null}]}
      """#

    XCTAssertEqual(["https://a.test/ok", "https://a.test/v"], try parse(json).entries.map(\.url))
  }

  func testJsonNullComesBackAsNull() throws {
    let info = try parse(
      #"{"_type":"video","title":null,"thumbnail":null,"duration":null,"uploader":null,"formats":null}"#)

    XCTAssertEqual(url, info.title)
    XCTAssertNil(info.thumbnail)
    XCTAssertNil(info.durationSeconds)
    XCTAssertNil(info.uploader)
    XCTAssertEqual(bare(tiers), info.options)
  }

  func testNullFieldsParseAsAbsent() throws {
    let info = try parse(#"{"title":null,"duration":null,"uploader":null,"formats":[]}"#)

    XCTAssertEqual(url, info.title)
    XCTAssertNil(info.durationSeconds)
    XCTAssertNil(info.uploader)
  }

  func testMissingKeysComeBackAsNull() throws {
    let info = try parse("{}")

    XCTAssertEqual(url, info.title)
    XCTAssertNil(info.thumbnail)
    XCTAssertNil(info.durationSeconds)
    XCTAssertNil(info.uploader)
    XCTAssertFalse(info.isPlaylist)
  }

  func testLiveStreamIsFlagged() throws {
    XCTAssertTrue(try parse(#"{"_type":"video","is_live":true}"#).isLive)
  }

  func testIsLiveDefaultsToFalse() throws {
    XCTAssertFalse(try parse("{}").isLive)
    XCTAssertFalse(try parse(#"{"is_live":null}"#).isLive)
    XCTAssertFalse(try parse(infoFixture("video")).isLive)
    XCTAssertFalse(try parse(infoFixture("playlist")).isLive)
  }

  func testNullEntryFieldsStayNull() throws {
    let json = #"""
      {"_type":"playlist","title":"P","entries":[
        {"url":"https://a.test/1","title":null,"thumbnail":null,"thumbnails":null,"duration":null}]}
      """#
    let entries = try parse(json).entries

    XCTAssertEqual(1, entries.count)
    XCTAssertEqual("https://a.test/1", entries.first?.title)
    XCTAssertNil(entries.first?.thumbnail)
    XCTAssertNil(entries.first?.durationSeconds)
  }

  func testThumbnailFallsBackToLastOfThumbnails() throws {
    let json = #"{"thumbnails":[{"url":"https://a.test/small.jpg"},{"url":"https://a.test/big.jpg"}]}"#

    XCTAssertEqual("https://a.test/big.jpg", try parse(json).thumbnail)
  }

  func testEntryUsesWebpageUrlWhenUrlIsMissing() throws {
    let json = #"{"_type":"playlist","entries":[{"webpage_url":"https://a.test/w","title":"W"}]}"#

    XCTAssertEqual(["https://a.test/w"], try parse(json).entries.map(\.url))
  }

  func testEntriesWithoutAnyUrlAreSkipped() throws {
    let json = #"{"_type":"playlist","entries":[{"title":"no url"},null,{"url":"https://a.test/ok","title":"ok"}]}"#

    XCTAssertEqual(["https://a.test/ok"], try parse(json).entries.map(\.url))
  }

  func testMultiVideoIsAPlaylist() throws {
    let info = try parse(#"{"_type":"multi_video","entries":[{"url":"https://a.test/1","title":"one"}]}"#)

    XCTAssertTrue(info.isPlaylist)
    XCTAssertEqual(bare(tiers), info.options)
    XCTAssertEqual(1, info.entries.count)
  }

  func testGarbageThrows() {
    XCTAssertThrowsError(try parse("ERROR: not json"))
    XCTAssertThrowsError(try parse("[1, 2]"))
  }

  func testPlaylistNeverOffersACover() throws {
    let json = #"{"_type":"playlist","thumbnail":"https://a.test/p.jpg","entries":[]}"#

    XCTAssertEqual(tiers, try parse(json).options.qualities())
  }

  func testNoFormatsOffersEveryQualityWithoutMetadata() throws {
    XCTAssertEqual(bare(tiers), try parse(#"{"formats":null}"#).options)
    XCTAssertEqual(bare(tiers), try parse(#"{"formats":[]}"#).options)
  }

  func testCoverFollowsTheThumbnailAndTakesItsSizeFromTheMatchingEntry() throws {
    let withEntry = #"""
      {"thumbnail":"https://a.test/t.jpg","thumbnails":[
        {"url":"https://a.test/small.jpg","width":10,"height":10},
        {"url":"https://a.test/t.jpg","width":640,"height":360}]}
      """#
    let withoutEntry = #"""
      {"thumbnail":"https://a.test/other.jpg","thumbnails":[
        {"url":"https://a.test/t.jpg","width":640,"height":360}]}
      """#

    XCTAssertEqual(opt(.cover, 640, 360), try parse(withEntry).options.last)
    XCTAssertEqual(opt(.cover), try parse(withoutEntry).options.last)
    XCTAssertFalse(try parse(#"{"formats":null}"#).options.contains { $0.quality == .cover })
  }

  func testCoverIsOfferedWhenOnlyTheThumbnailsListHasAnImage() throws {
    XCTAssertEqual(.cover, try parse(#"{"thumbnails":[{"url":"https://a.test/big.jpg"}]}"#).options.last?.quality)
  }

  func testOnlyNoneVideoCodecsOffersMp3Only() throws {
    let storyboard = #"{"vcodec":"none","acodec":"none","width":320,"height":180}"#

    XCTAssertEqual([opt(.mp3, nil, nil, nil, 1000, true)], try options(audio(extra: size(1000)), storyboard))
  }

  func testStoryboardsAloneStillOfferMp3WithoutASize() throws {
    let storyboard = #"{"vcodec":"none","acodec":"none","width":320,"height":180}"#

    XCTAssertEqual([opt(.mp3, nil, nil, nil, nil, true)], try options(storyboard))
  }

  func testVideoWithoutDimensionsOffersBestAndMp3WithoutMetadata() throws {
    let noSize = #"{"vcodec":"avc1.4D401F","acodec":"mp4a.40.2"}"#
    let nullSize = #"{"vcodec":"avc1.4D401F","height":null,"width":null}"#
    let heightOnly = #"{"vcodec":"avc1.4D401F","acodec":"mp4a.40.2","height":720}"#

    XCTAssertEqual(bare([.best]) + [opt(.mp3, nil, nil, nil, nil, true)], try options(noSize))
    XCTAssertEqual(
      bare([.best]) + [opt(.mp3, nil, nil, nil, 500, true)], try options(audio(extra: size(500)), nullSize))
    XCTAssertEqual([.best, .mp3], try options(heightOnly).qualities())
  }

  func testVideoOnlyWithoutAnyAudioOffersNoMp3() throws {
    XCTAssertEqual([.best], try options(video(1280, 720)).qualities())
  }

  func testMissingVideoCodecCountsAsVideoWithSoundUnknown() throws {
    let offered = try options(#"{"width":1280,"height":720}"#)

    XCTAssertEqual([.best, .mp3], offered.qualities())
    XCTAssertEqual(1280, offered.first?.width)
    XCTAssertEqual(720, offered.first?.height)
  }

  func testASingleStreamCollapsesEveryTierIntoBest() throws {
    for (width, height) in [(1920, 1080), (1080, 1920), (2560, 1440), (320, 240)] {
      let offered = try options(video(width, height), audio()).qualities()

      XCTAssertEqual([.best, .mp3], offered, "\(width)x\(height)")
    }
  }

  func testCapsUseTheShorterSideForLandscapeAndPortrait() throws {
    let landscape = try options(video(2560, 1440), video(1920, 1080), video(1280, 720), video(854, 480), audio())
    let portrait = try options(video(1440, 2560), video(1080, 1920), video(720, 1280), video(480, 854), audio())

    for offered in [landscape, portrait] {
      XCTAssertEqual(tiers, offered.qualities())
      let shortSides = offered.filter { $0.quality != .mp3 }.map { min($0.width!, $0.height!) }
      XCTAssertEqual([1440, 1080, 720, 480], shortSides)
    }
  }

  func testATierWithNothingUnderItsCapTakesTheSmallestStreamAbove() throws {
    let offered = try options(video(1080, 1920), video(576, 1024), audio())

    XCTAssertEqual([.best, .p720, .mp3], offered.qualities())
    XCTAssertEqual(576, try offered.of(.p720).width)
  }

  func testAStreamAboveItsCapIsNotPickedWhileOneFits() throws {
    let offered = try options(video(1920, 1080), video(1280, 720), audio())

    XCTAssertEqual([.best, .p720, .mp3], offered.qualities())
    XCTAssertEqual(1920, try offered.of(.best).width)
    XCTAssertEqual(1280, try offered.of(.p720).width)
  }

  func testStoryboardDimensionsAreIgnored() throws {
    let storyboard = #"{"vcodec":"none","acodec":"none","width":1920,"height":1080}"#

    let offered = try options(storyboard, video(1280, 720), audio())

    XCTAssertEqual(720, try offered.of(.best).height)
    XCTAssertEqual([.best, .mp3], offered.qualities())
  }

  func testH264BeatsHigherBitrateOnTheSameShortSide() throws {
    func stream(_ vcodec: String, _ bytes: Int64, _ tbr: Int) -> String {
      video(1280, 720, vcodec: vcodec, acodec: "aac", extra: size(bytes) + #","tbr":\#(tbr)"#)
    }
    let vp9 = stream("vp09.00.40.08", 900, 3000)
    let h264 = stream("avc1.64001F", 100, 500)
    let legacy = stream("h264", 300, 100)

    XCTAssertEqual(100, try options(vp9, h264).of(.best).sizeBytes)
    XCTAssertEqual(300, try options(h264, legacy).of(.best).sizeBytes)
    XCTAssertEqual(300, try options(vp9, legacy).of(.best).sizeBytes)
  }

  func testWithoutH264TheCodecClosestToItWins() throws {
    func stream(_ vcodec: String, _ bytes: Int64, _ tbr: Int) -> String {
      video(3840, 2160, vcodec: vcodec, acodec: "aac", extra: size(bytes) + #","tbr":\#(tbr)"#)
    }
    let vp9 = stream("vp09.00.50.08", 100, 8000)
    let av1 = stream("av01.0.12M.08", 200, 12000)
    let hevc = stream("hvc1.1.6.L153", 300, 6000)
    let vp8 = stream("vp8", 400, 1000)

    XCTAssertEqual(100, try options(vp9, av1).of(.best).sizeBytes)
    XCTAssertEqual(300, try options(vp9, av1, hevc).of(.best).sizeBytes)
    XCTAssertEqual(400, try options(vp9, hevc, vp8).of(.best).sizeBytes)
  }

  func testAProgressiveAacStreamBeatsAFasterVideoOnlyOneOfTheSameCodec() throws {
    let progressive = video(1280, 720, acodec: "mp4a.40.2", extra: size(1000) + #","fps":30"#)
    let videoOnly = video(1280, 720, extra: size(900) + #","fps":60"#)

    let best = try options(progressive, videoOnly, audio("mp4a.40.2", extra: size(300))).of(.best)

    XCTAssertEqual(1000, best.sizeBytes)
    XCTAssertEqual(30, best.fps)
  }

  func testFrameRateThenSizeThenBitrateBreakTheTie() throws {
    func stream(_ bytes: Int64, _ fps: Int, _ tbr: Int) -> String {
      video(1280, 720, acodec: "aac", extra: size(bytes) + #","fps":\#(fps),"tbr":\#(tbr)"#)
    }
    let slow = stream(10, 30, 5000)
    let fast = stream(20, 60, 100)
    let fastHeavy = stream(30, 60, 200)

    XCTAssertEqual(20, try options(slow, fast).of(.best).sizeBytes)
    XCTAssertEqual(30, try options(slow, fast, fastHeavy).of(.best).sizeBytes)
    XCTAssertEqual(60, try options(slow, fast).of(.best).fps)

    let low = video(1280, 720, acodec: "aac", extra: #","tbr":100"#)
    let high = video(1280, 720, acodec: "aac", extra: #","tbr":200"#)
    XCTAssertEqual(2_500_000, try options(low, high).of(.best).sizeBytes)
  }

  func testVideoOnlyPickIsMergedWithTheBestAudio() throws {
    let v = video(1280, 720, extra: size(1000))
    let opusLoud = audio("opus", extra: size(400) + #","abr":160"#)
    let aacQuiet = audio("mp4a.40.2", extra: size(300) + #","abr":128"#)
    let aacLouder = audio("mp4a.40.2", extra: size(350) + #","abr":140"#)

    XCTAssertEqual(1300, try options(v, opusLoud, aacQuiet).of(.best).sizeBytes)
    XCTAssertEqual(1350, try options(v, opusLoud, aacQuiet, aacLouder).of(.best).sizeBytes)
    XCTAssertEqual(400, try options(v, opusLoud).of(.mp3).sizeBytes)
  }

  func testAudioFallsBackToTbrWhenAbrIsMissingOrZero() throws {
    let v = video(1280, 720, extra: size(1000))
    let small = audio("opus", extra: size(100) + #","abr":0,"tbr":64"#)
    let big = audio("opus", extra: size(200) + #","abr":0,"tbr":128"#)

    XCTAssertEqual(1200, try options(v, small, big).of(.best).sizeBytes)
  }

  func testProgressivePickDoesNotAddAudio() throws {
    let progressive = video(1280, 720, acodec: "mp4a.40.2", extra: size(1000))

    XCTAssertEqual(1000, try options(progressive, audio(extra: size(400))).of(.best).sizeBytes)
    XCTAssertEqual(1000, try options(video(1280, 720, acodec: "aac", extra: size(1000))).of(.best).sizeBytes)
  }

  func testMissingAudioCodecIsTreatedAsProgressive() throws {
    let unknown = #"{"vcodec":"avc1.4D401F","width":1280,"height":720,"filesize":1000}"#

    XCTAssertEqual(1000, try options(unknown, audio(extra: size(400))).of(.best).sizeBytes)
  }

  func testExactSizeIsNotAnEstimate() throws {
    let offered = try options(video(1280, 720, extra: size(1000)), audio(extra: size(200)))

    XCTAssertEqual(opt(.best, 1280, 720, nil, 1200), try offered.of(.best))
  }

  func testApproximateSizeIsFlaggedAsAnEstimate() throws {
    let offered = try options(video(1280, 720, extra: #","filesize_approx":1000"#), audio(extra: size(200)))

    XCTAssertEqual(1200, try offered.of(.best).sizeBytes)
    XCTAssertTrue(try offered.of(.best).sizeIsEstimate)
  }

  func testExactFilesizeWinsOverTheApproximation() throws {
    let v = video(1280, 720, extra: size(1000) + #","filesize_approx":5000"#)

    let best = try options(v, audio(extra: size(200))).of(.best)

    XCTAssertEqual(1200, best.sizeBytes)
    XCTAssertFalse(best.sizeIsEstimate)
  }

  func testBitrateTimesDurationIsTheLastResort() throws {
    let v = video(1280, 720, extra: size(1000))
    let a = audio("opus", extra: #","tbr":64"#)

    let best = try options(v, a, duration: "10").of(.best)

    XCTAssertEqual(1000 + 80_000, best.sizeBytes)
    XCTAssertTrue(best.sizeIsEstimate)
    XCTAssertEqual(80_000, try options(v, a, duration: "10").of(.mp3).sizeBytes)
  }

  func testBitrateEstimateNeedsADuration() throws {
    let progressive = video(1280, 720, acodec: "aac", extra: #","tbr":800"#)

    XCTAssertNil(try options(progressive, duration: "null").of(.best).sizeBytes)
    XCTAssertEqual(10_000_000, try options(progressive).of(.best).sizeBytes)
  }

  func testAnUnknownPartLeavesTheSizeNull() throws {
    let v = video(1280, 720, extra: size(1000))

    let best = try options(v, audio()).of(.best)

    XCTAssertNil(best.sizeBytes)
    XCTAssertFalse(best.sizeIsEstimate)
    XCTAssertNil(try options(video(1280, 720), audio(extra: size(200))).of(.best).sizeBytes)
  }

  func testMp3SizeIsAlwaysAnEstimateAndNullWithoutAudioStream() throws {
    let progressive = video(1280, 720, acodec: "aac", extra: size(1000))

    XCTAssertTrue(try options(progressive).of(.mp3).sizeIsEstimate)
    XCTAssertNil(try options(progressive).of(.mp3).sizeBytes)
    XCTAssertEqual(250, try options(progressive, audio(extra: size(250))).of(.mp3).sizeBytes)
  }
}
