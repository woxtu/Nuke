// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

@available(*, deprecated)
class DeprecatedImageViewTests: XCTestCase {
    var imageView: _ImageView!
    var mockPipeline: MockImagePipeline!
    var mockCache: MockImageCache!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        mockPipeline = MockImagePipeline {
            $0.imageCache = mockCache
        }

        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(mockPipeline)

        imageView = _ImageView()
    }

    override func tearDown() {
        ImagePipeline.popShared()
    }

    // MARK: - Loading

    func testImageLoaded() {
        // When requesting an image with request
        expectToLoadImage(with: Test.request, into: imageView)
        wait()

        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(imageView.image)
    }

    func testImageLoadedWithURL() {
        // When requesting an image with URL
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: Test.url, into: imageView) { response, _ in
            expectation.fulfill()
        }
        wait()

        // Expect the image to be downloaded and displayed
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Managing Tasks

    func testTaskReturned() {
        // When requesting an image
        let task = Nuke.loadImage(with: Test.request, into: imageView)

        // Expect Nuke to return a task
        XCTAssertNotNil(task)

        // Expect the task's request to be equivalent to the one provided
        XCTAssertEqual(task?.request.urlRequest, Test.request.urlRequest)
    }

    func testTaskIsNilWhenImageInMemoryCache() {
        // When the requested image is stored in memory cache
        let request = Test.request
        mockCache[request] = Image()

        // When requesting an image
        let task = Nuke.loadImage(with: request, into: imageView)

        // Expect Nuke to not return any tasks
        XCTAssertNil(task)
    }

    // MARK: - Prepare For Reuse

    func testViewPreparedForReuse() {
        // Given an image view displaying an image
        imageView.image = Test.image

        // When requesting the new image
        Nuke.loadImage(with: Test.request, into: imageView)

        // Then
        XCTAssertNil(imageView.image)
    }

    func testViewPreparedForReuseDisabled() {
        // Given an image view displaying an image
        let image = Test.image
        imageView.image = image

        // When requesting the new image with prepare for reuse disabled
        var options = ImageLoadingOptions()
        options.isPrepareForReuseEnabled = false
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Expect the original image to still be displayed
        XCTAssertEqual(imageView.image, image)
    }

    // MARK: - Memory Cache

    func testMemoryCacheUsed() {
        // Given the requested image stored in memory cache
        let image = Test.image
        mockCache[Test.request] = image

        // When requesting the new image
        Nuke.loadImage(with: Test.request, into: imageView)

        // Expect image to be displayed immediatelly
        XCTAssertEqual(imageView.image, image)
    }

    func testMemoryCacheDisabled() {
        // Given the requested image stored in memory cache
        mockCache[Test.request] = Test.image

        // When requesting the image with memory cache read disabled
        var request = Test.request
        request.memoryCacheOptions.isReadAllowed = false
        Nuke.loadImage(with: request, into: imageView)

        // Expect image to not be displayed, loaded asyncrounously instead
        XCTAssertNil(imageView.image)
    }

    // MARK: - Completion and Progress Closures

    func testCompletionCalled() {
        var didCallCompletion = false
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _ in
                // Expect completion to be called  on the main thread
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                didCallCompletion = true
                expectation.fulfill()
        }
        )

        // Expect completion to be called asynchronously
        XCTAssertFalse(didCallCompletion)
        wait()
    }

    func testCompletionCalledImageFromCache() {
        // Given the requested image stored in memory cache
        mockCache[Test.request] = Test.image

        var didCallCompletion = false
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            completion: { response, _ in
                // Expect completion to be called syncrhonously on the main thread
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertNotNil(response)
                didCallCompletion = true
        }
        )
        XCTAssertTrue(didCallCompletion)
    }

    func testProgressHandlerCalled() {
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        // When loading an image into a view
        Nuke.loadImage(
            with: Test.request,
            into: imageView,
            progress: { _, completed, total in
                // Expect progress to be reported, on the main thread
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((completed, total))
        }
        )

        wait()
    }

    // MARK: - Cancellation

    func testRequestCancelled() {
        mockPipeline.queue.isSuspended = true

        // Given an image view with an associated image task
        expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        // Expect the task to get cancelled
        expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)

        // When asking Nuke to cancel the request for the view
        Nuke.cancelRequest(for: imageView)
        wait()
    }

    func testRequestCancelledWhenNewRequestStarted() {
        mockPipeline.queue.isSuspended = true

        // Given an image view with an associated image task
        expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()

        // When starting loading a new image
        // Expect previous task to get cancelled
        expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)
        Nuke.loadImage(with: Test.url, into: imageView)
        wait()
    }

    func testRequestCancelledWhenTargetGetsDeallocated() {
        mockPipeline.queue.isSuspended = true

        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            // Given an image view with an associated image task
            var imageView: _ImageView! = _ImageView()
            expectNotification(MockImagePipeline.DidStartTask, object: mockPipeline)
            Nuke.loadImage(with: Test.url, into: imageView)
            wait()

            // Expect the task to be cancelled automatically
            expectNotification(MockImagePipeline.DidCancelTask, object: mockPipeline)

            // When the view is deallocated
            imageView = nil
        }
        wait()
    }

    func testCancellingTheTaskAndWaitingForCompletion() {
        mockPipeline.queue.isSuspended = true

        // Given pipeline with cancellation disabled (important!)
        mockPipeline.isCancellationEnabled = false

        // Given an image view which is in the process of loading the image
        Nuke.loadImage(with: Test.request, into: imageView) { _, _ in
            // Expect completion to never get called, we're already displaying
            // the image B by that point.
            XCTFail("Enexpected completion")
        }

        // When cancelling the request
        Nuke.cancelRequest(for: imageView)

        // When the pipeline finishes loading the image B.
        expectNotification(MockImagePipeline.DidFinishTask)
        mockPipeline.queue.isSuspended = false
        wait()

        // Expect an image view to still be displaying the image B.
        XCTAssertNil(imageView.image)
    }

    func testCancellingTheTaskByRequestingNewImageStoredInCache() {
        mockPipeline.queue.isSuspended = true

        let requestA = ImageRequest(url: URL(string: "test://imageA")!)
        let requestB = ImageRequest(url: URL(string: "test://imageB")!)

        // Given pipeline with cancellation disabled (important!)
        mockPipeline.isCancellationEnabled = false

        // Given an image A not stored in cache and image B - stored.
        let imageB = Image()
        mockCache[requestB] = imageB

        // Given an image view which is in the process of loading the image A.
        Nuke.loadImage(with: requestA, into: imageView) { _, _ in
            // Expect completion to never get called, we're already displaying
            // the image B by that point.
            XCTFail("Enexpected completion for requestA")
        }

        // When starting a starting a new request for the image B.
        Nuke.loadImage(with: requestB, into: imageView)

        // Expect an image B to be displayed immediatelly.
        XCTAssertEqual(imageB, imageView.image)

        // When the pipeline finishes loading the image B.
        expectNotification(MockImagePipeline.DidFinishTask)
        mockPipeline.queue.isSuspended = false
        wait()

        // Expect an image view to still be displaying the image B.
        XCTAssertEqual(imageB, imageView.image)
    }
}

@available(*, deprecated)
class DeprecatedImageViewLoadingOptionsTests: XCTestCase {
    var mockCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var imageView: _ImageView!

    override func setUp() {
        super.setUp()

        mockCache = MockImageCache()
        dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = mockCache
        }
        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(pipeline)

        imageView = _ImageView()
    }

    override func tearDown() {
        ImagePipeline.popShared()
    }

    // MARK: - Transition

    func testCustomTransitionPerformed() {
        // Given
        var options = ImageLoadingOptions()

        let expectTransition = self.expectation(description: "")
        options.transition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertNil(self.imageView.image) // Image isn't displayed automatically.
            XCTAssertEqual(view, self.imageView)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()
    }

    // Tests https://github.com/kean/Nuke/issues/206
    func testImageIsDisplayedFadeInTransition() {
        // Given options with .fadeIn transition
        let options = ImageLoadingOptions(transition: .fadeIn(duration: 10))

        // When loading an image into an image view
        expectToLoadImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then image is actually displayed
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Placeholder

    func testPlaceholderDisplayed() {
        // Given
        var options = ImageLoadingOptions()
        let placeholder = Image()
        options.placeholder = placeholder

        // When
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, placeholder)
    }

    // MARK: - Failure Image

    func testFailureImageDisplayed() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "ErrorDomain", code: 42, userInfo: nil)
        )

        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }

    func testFailureImageTransitionRun() {
        // Given
        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        var options = ImageLoadingOptions()
        let failureImage = Image()
        options.failureImage = failureImage

        // Given
        let expectTransition = self.expectation(description: "")
        options.failureImageTransition = .custom({ (view, image) in
            // Then
            XCTAssertEqual(view, self.imageView)
            XCTAssertEqual(image, failureImage)
            self.imageView.image = image
            expectTransition.fulfill()
        })

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.image, failureImage)
    }

    #if !os(macOS)

    // MARK: - Content Modes

    func testPlaceholderAndSuccessContentModesApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = .init(
            success: .scaleAspectFill, // default is .scaleToFill
            failure: .center,
            placeholder: .center
        )
        options.placeholder = Image()

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.contentMode, .center)
        wait()
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testSuccessContentModeAppliedWhenFromMemoryCache() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )

        mockCache[Test.request] = Test.image

        // Whem
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.contentMode, .scaleAspectFill)
    }

    func testFailureContentModeApplied() {
        // Given
        var options = ImageLoadingOptions()
        options.contentModes = ImageLoadingOptions.ContentModes(
            success: .scaleAspectFill,
            failure: .center,
            placeholder: .center
        )
        options.failureImage = Image()

        dataLoader.results[Test.url] = .failure(
            NSError(domain: "t", code: 42, userInfo: nil)
        )

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)
        wait()

        // Then
        XCTAssertEqual(imageView.contentMode, .center)
    }

    #endif

    // MARK: - Pipeline

    func testCustomPipelineUsed() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        var options = ImageLoadingOptions()
        options.pipeline = pipeline

        // When
        expectToFinishLoadingImage(with: Test.request, options: options, into: imageView)

        // Then
        wait { _ in
            _ = pipeline
            XCTAssertEqual(dataLoader.createdTaskCount, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 0)
        }
    }

    // MARK: - Shared Options

    func testSharedOptionsUsed() {
        // Given
        var options = ImageLoadingOptions.shared
        let placeholder = Image()
        options.placeholder = placeholder

        ImageLoadingOptions.pushShared(options)

        // When
        Nuke.loadImage(with: Test.request, options: options, into: imageView)

        // Then
        XCTAssertEqual(imageView.image, placeholder)

        ImageLoadingOptions.popShared()

    }
}

@available(*, deprecated)
class DeprecatedImageRequestTests: XCTestCase {
    // MARK: - CoW

    func testStructSemanticsArePreserved() {
        // Given
        let url1 =  URL(string: "http://test.com/1.png")!
        let url2 = URL(string: "http://test.com/2.png")!
        var request = ImageRequest(url: url1)

        // When
        var copy = request
        copy.urlRequest = URLRequest(url: url2)

        // Then
        XCTAssertEqual(url2, copy.urlRequest.url)
        XCTAssertEqual(url1, request.urlRequest.url)
    }

    func testCopyOnWrite() {
        // Given
        var request = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        request.memoryCacheOptions.isReadAllowed = false
        request.loadKey = "1"
        request.cacheKey = "2"
        request.userInfo = "3"
        request.processor = MockImageProcessor(id: "4")
        request.priority = .high

        // When
        var copy = request
        // Requst makes a copy at this point under the hood.
        copy.urlRequest = URLRequest(url: URL(string: "http://test.com/2.png")!)

        // Then
        XCTAssertEqual(copy.memoryCacheOptions.isReadAllowed, false)
        XCTAssertEqual(copy.loadKey, "1")
        XCTAssertEqual(copy.cacheKey, "2")
        XCTAssertEqual(copy.userInfo as? String, "3")
        XCTAssertEqual((copy.processor as? MockImageProcessor)?.identifier, MockImageProcessor(id: "4").identifier)
        XCTAssertEqual(copy.priority, .high)
    }

    // MARK: - Misc

    // Just to make sure that comparison works as expected.
    func testPriorityComparison() {
        typealias Priority = ImageRequest.Priority
        XCTAssertTrue(Priority.veryLow < Priority.veryHigh)
        XCTAssertTrue(Priority.low < Priority.normal)
        XCTAssertTrue(Priority.normal == Priority.normal)
    }
}

@available(*, deprecated)
class DeprecatedImageRequestCacheKeyTests: XCTestCase {
    func testDefaults() {
        let request = Test.request
        AssertHashableEqual(CacheKey(request: request), CacheKey(request: request)) // equal to itself
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDefaultURLRequestAndURLAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testURLRequestParametersAreIgnored() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testSettingDefaultProcessorManually() {
        let request1 = ImageRequest(url: Test.url)
        var request2 = ImageRequest(url: Test.url)
        request2.processor = request1.processor
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    // MARK: Custom Cache Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.cacheKey = "1"
        AssertHashableEqual(CacheKey(request: request1), CacheKey(request: request2))
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.cacheKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.cacheKey = "2"
        XCTAssertNotEqual(CacheKey(request: request1), CacheKey(request: request2))
    }
}

@available(*, deprecated)
class DeprecatedImageRequestLoadKeyTests: XCTestCase {
    func testDefaults() {
        let request = ImageRequest(url: Test.url)
        AssertHashableEqual(LoadKey(request: request), LoadKey(request: request))
    }

    func testRequestsWithTheSameURLsAreEquivalent() {
        let request1 = ImageRequest(url: Test.url)
        let request2 = ImageRequest(url: Test.url)
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithDifferentURLsAreNotEquivalent() {
        let request1 = ImageRequest(url: URL(string: "http://test.com/1.png")!)
        let request2 = ImageRequest(url: URL(string: "http://test.com/2.png")!)
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestWithDifferentURLRequestParametersAreNotEquivalent() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 50))
        let request2 = ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    // MARK: - Custom Load Key

    func testRequestsWithSameCustomKeysAreEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "1"
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithSameCustomKeysButDifferentURLsAreEquivalent() {
        var request1 = ImageRequest(url: URL(string: "https://example.com/photo1.jpg")!)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: URL(string: "https://example.com/photo2.jpg")!)
        request2.loadKey = "1"
        AssertHashableEqual(LoadKey(request: request1), LoadKey(request: request2))
    }

    func testRequestsWithDifferentCustomKeysAreNotEquivalent() {
        var request1 = ImageRequest(url: Test.url)
        request1.loadKey = "1"
        var request2 = ImageRequest(url: Test.url)
        request2.loadKey = "2"
        XCTAssertNotEqual(LoadKey(request: request1), LoadKey(request: request2))
    }
}

private typealias CacheKey = ImageRequest.CacheKey
private typealias LoadKey = ImageRequest.LoadKey

private func AssertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}
