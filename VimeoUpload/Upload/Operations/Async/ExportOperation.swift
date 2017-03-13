//
//  ExportOperation.swift
//  VimeoUpload
//
//  Created by Hanssen, Alfie on 10/13/15.
//  Copyright © 2015 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import AVFoundation

#if os(iOS)
    import MobileCoreServices
#elseif os(OSX)
    import CoreServices
#endif

open class ExportOperation: ConcurrentOperation
{
    fileprivate static let ProgressKeyPath = "progress"
    fileprivate static let FileType = AVFileTypeMPEG4

    fileprivate(set) var exportSession: AVAssetExportSession
    
    // We KVO on this internally in order to call the progressBlock, see note below as to why [AH] 10/22/2015
    fileprivate dynamic var progress: Float = 0
    fileprivate var exportProgressKVOContext = UInt8()
    var progressBlock: ProgressBlock?
    
    fileprivate(set) var outputURL: URL?
    fileprivate(set) var error: NSError?
    
    // MARK: - Initialization
    
    convenience init(asset: AVAsset)
    {
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)!
        
        self.init(exportSession: exportSession)
    }

    init(exportSession: AVAssetExportSession)
    {
        // exportSession.timeRange must be valid so that the exportSession's estimatedOutputFileLength is non zero
        // We use estimatedOutputFileLength below to check that there is ample disk space to perform the export [AH] 10/15/2015
        
        exportSession.timeRange = CMTimeRangeMake(kCMTimeZero, exportSession.asset.duration)

        assert(CMTIMERANGE_IS_EMPTY(exportSession.timeRange) == false, "exportSession.timeRange is empty")
        assert(CMTIMERANGE_IS_INDEFINITE(exportSession.timeRange) == false, "exportSession.timeRange is indefinite")
        assert(CMTIMERANGE_IS_INVALID(exportSession.timeRange) == false, "exportSession.timeRange is invalid")
        assert(CMTIMERANGE_IS_VALID(exportSession.timeRange) == true, "exportSession.timeRange is not valid")
        assert(CMTIME_IS_POSITIVEINFINITY(exportSession.timeRange.duration) == false, "exportSession.timeRange.duration is infinite")
        
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.outputFileType = ExportOperation.FileType

        do
        {
            let filename = ProcessInfo.processInfo.globallyUniqueString
            exportSession.outputURL = try URL.uploadURLWithFilename(filename, fileType: type(of: self).FileType)
        }
        catch let error as NSError
        {
            fatalError("Error creating upload export directory: \(error.localizedDescription)")
        }

        self.exportSession = exportSession
        
        super.init()
        
        self.addObservers()
    }
    
    deinit
    {
        self.removeObservers()
        self.progressBlock = nil
        self.exportSession.cancelExport()
    }

    // MARK: Overrides

    override open func main()
    {
        if self.isCancelled
        {
            return
        }
        
        if self.exportSession.asset.isExportable == false // DRM protected
        {
            self.error = NSError.errorWithDomain(UploadErrorDomain.ExportOperation.rawValue, code: UploadLocalErrorCode.assetIsNotExportable.rawValue, description: "Asset is not exportable")
            self.state = .finished
            
            return
        }

        // AVAssetExportSession does not do an internal check to see if there's ample disk space available to perform the export [AH] 12/06/2015
        // However this check will not work with presetName "passthrough" since that preset reports estimatedOutputFileLength of zero always.

        let availableDiskSpace = try? FileManager.default.availableDiskSpace() // Double optional
        if let diskSpace = availableDiskSpace, let space = diskSpace, space.int64Value < self.exportSession.estimatedOutputFileLength
        {
            self.error = NSError.errorWithDomain(UploadErrorDomain.ExportOperation.rawValue, code: UploadLocalErrorCode.diskSpaceException.rawValue, description: "Not enough disk space to copy asset")
            self.state = .finished
            
            return
        }
        
        self.exportSession.exportAsynchronously(completionHandler: { [weak self] () -> Void in
            
            guard let strongSelf = self else
            {
                return
            }
            
            if strongSelf.isCancelled
            {
                return
            }
            
            if let error = strongSelf.exportSession.error
            {
                strongSelf.error = error.errorByAddingDomain(UploadErrorDomain.ExportOperation.rawValue)

                if error.domain == AVFoundationErrorDomain && error.code == AVError.Code.diskFull.rawValue
                {
                    strongSelf.error = error.errorByAddingDomain(UploadErrorDomain.ExportOperation.rawValue).errorByAddingCode(UploadLocalErrorCode.diskSpaceException.rawValue)
                }
                else
                {
                    strongSelf.error = error.errorByAddingDomain(UploadErrorDomain.ExportOperation.rawValue)
                }
            }
            else if let outputURL = strongSelf.exportSession.outputURL, let path = outputURL.path, FileManager.default.fileExists(atPath: path)
            {
                strongSelf.outputURL = outputURL
            }
            else
            {
                strongSelf.error = NSError.errorWithDomain(UploadErrorDomain.ExportOperation.rawValue, code: nil, description: "Export session finished with no error and no output URL.")
            }

            strongSelf.state = .finished
        })

        // For some reason, not sure why, KVO on self.exportSession.progress does not trigger calls to observeValueForKeyPath
        // So I'm using this while loop to update a dynamic property instead, and KVO'ing on that [AH] 10/22/2015
        
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.low).async { [weak self] () -> Void in
            while self?.exportSession.status == AVAssetExportSessionStatus.waiting || self?.exportSession.status == AVAssetExportSessionStatus.exporting
            {
                self?.progress = self?.exportSession.progress ?? 0
            }
        }
    }
    
    override open func cancel()
    {
        super.cancel()
        
        self.progressBlock = nil
        self.exportSession.cancelExport()
    }
        
    // MARK: KVO
    
    fileprivate func addObservers()
    {
        self.addObserver(self, forKeyPath: type(of: self).ProgressKeyPath, options: NSKeyValueObservingOptions.new, context: &self.exportProgressKVOContext)
    }
    
    fileprivate func removeObservers()
    {
        self.removeObserver(self, forKeyPath: type(of: self).ProgressKeyPath, context: &self.exportProgressKVOContext)
    }
    
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
    {
        if let keyPath = keyPath
        {
            switch (keyPath, context)
            {
                case(type(of: self).ProgressKeyPath, self.exportProgressKVOContext):
                    let progress = (change?[NSKeyValueChangeKey.newKey] as AnyObject).doubleValue ?? 0;
                    self.progressBlock?(progress)
                
                default:
                    super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
        else
        {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }    
}
