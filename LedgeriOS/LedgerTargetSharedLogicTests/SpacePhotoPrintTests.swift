import Foundation
import ImageIO
import PDFKit
import Testing

@Suite("Reused Space photo printing")
struct SpacePhotoPrintTests {
    @Test func onePagePerPhoto() throws {
        let context = try #require(CGContext(data: nil,width: 2,height: 2,bitsPerComponent: 8,bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1,green: 0,blue: 0,alpha: 1))
        context.fill(CGRect(x: 0,y: 0,width: 2,height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil)
        #expect(CGImageDestinationFinalize(destination))
        let result = try PhotoPrintPresentation.makePDF(from: [data as Data,data as Data])
        let document = try #require(PDFDocument(data: result))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 612,height: 792))
    }

    @Test func noBlankSuccessForMissingOrInvalidImages() {
        #expect(throws: PhotoPrintError.self) { try PhotoPrintPresentation.makePDF(from: []) }
        #expect(throws: PhotoPrintError.self) { try PhotoPrintPresentation.makePDF(from: [Data("not an image".utf8)]) }
    }
}
