//
//  BarcodeScannerViewController.swift
//  barcode_scan
//
//  Created by Julian Finkler on 20.02.20.
//

import Foundation
import MTBBarcodeScanner

class BarcodeScannerViewController: UIViewController {
  private var previewView: UIView?
  private var scanRect: ScannerOverlay?
  private var scanner: MTBBarcodeScanner?
  private var useCamera = -1

  var config: Configuration = Configuration.with {
    $0.strings = [
      "title" : "",
      "cancel" : "Cancel",
      "flash_on" : "Flash on",
      "flash_off" : "Flash off",
      "switch": "Switch",
      "icon": "",
    ]
    $0.useCamera = -1 // Default camera
    $0.autoEnableFlash = false
  }

  private let formatMap = [
    BarcodeFormat.aztec : AVMetadataObject.ObjectType.aztec,
    BarcodeFormat.code39 : AVMetadataObject.ObjectType.code39,
    BarcodeFormat.code93 : AVMetadataObject.ObjectType.code93,
    BarcodeFormat.code128 : AVMetadataObject.ObjectType.code128,
    BarcodeFormat.dataMatrix : AVMetadataObject.ObjectType.dataMatrix,
    BarcodeFormat.ean8 : AVMetadataObject.ObjectType.ean8,
    BarcodeFormat.ean13 : AVMetadataObject.ObjectType.ean13,
    BarcodeFormat.interleaved2Of5 : AVMetadataObject.ObjectType.interleaved2of5,
    BarcodeFormat.pdf417 : AVMetadataObject.ObjectType.pdf417,
    BarcodeFormat.qr : AVMetadataObject.ObjectType.qr,
    BarcodeFormat.upce : AVMetadataObject.ObjectType.upce,
  ]

  var delegate: BarcodeScannerViewControllerDelegate?

  private var device: AVCaptureDevice? {
    return AVCaptureDevice.default(for: .video)
  }

  private var isFlashOn: Bool {
    return device != nil && (device?.flashMode == AVCaptureDevice.FlashMode.on || device?.torchMode == .on)
  }

  private var buttonText: Bool {
      return config.strings["icon"] != nil && (config.strings["icon"] != "true")
  }

  private var hasTorch: Bool {
    return device?.hasTorch ?? false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    #if targetEnvironment(simulator)
    view.backgroundColor = .lightGray
    #endif

    previewView = UIView(frame: view.bounds)
    if let previewView = previewView {
      previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(previewView)
    }
    setupScanRect(view.bounds)

    let restrictedBarcodeTypes = mapRestrictedBarcodeTypes()
    if restrictedBarcodeTypes.isEmpty {
      scanner = MTBBarcodeScanner(previewView: previewView)
    } else {
      scanner = MTBBarcodeScanner(metadataObjectTypes: restrictedBarcodeTypes,
                                  previewView: previewView
      )
    }

    if config.strings["icon"] != "true" {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: config.strings["cancel"],
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(cancel))
    } else {
        self.navigationController!.navigationBar.barStyle = .black
        self.navigationController!.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        self.title = config.strings["title"]
    
        let closeButton = UIButton(type: .custom)
        closeButton.setImage(UIImage(named: "ic_close"), for: .normal)
        closeButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: closeButton)
    }

    updateMenuButtons()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    if scanner!.isScanning() {
      scanner!.stopScanning()
    }

    scanRect?.startAnimating()
    MTBBarcodeScanner.requestCameraPermission(success: { success in
      if success {
        self.startScan()
      } else {
        #if !targetEnvironment(simulator)
        self.errorResult(errorCode: "PERMISSION_NOT_GRANTED")
        #endif
      }
    })
  }

  override func viewWillDisappear(_ animated: Bool) {
    scanner?.stopScanning()
    scanRect?.stopAnimating()

    if isFlashOn {
      setFlashState(false)
    }

    super.viewWillDisappear(animated)
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    setupScanRect(CGRect(origin: CGPoint(x: 0, y:0),
                         size: size
    ))
  }

  private func setupScanRect(_ bounds: CGRect) {
    if scanRect != nil {
      scanRect?.stopAnimating()
      scanRect?.removeFromSuperview()
    }
    scanRect = ScannerOverlay(frame: bounds)
    if let scanRect = scanRect {
      scanRect.translatesAutoresizingMaskIntoConstraints = false
      scanRect.backgroundColor = UIColor.clear
      view.addSubview(scanRect)
      scanRect.startAnimating()
    }
  }

  private func startScan() {
    do {
      try scanner!.startScanning(with: cameraFromConfig, resultBlock: { codes in
        if let code = codes?.first {
          let codeType = self.formatMap.first(where: { $0.value == code.type });
          let scanResult = ScanResult.with {
            $0.type = .barcode
            $0.rawContent = code.stringValue ?? ""
            $0.format = codeType?.key ?? .unknown
            $0.formatNote = codeType == nil ? code.type.rawValue : ""
          }
          self.scanner!.stopScanning()
          self.scanResult(scanResult)
        }
      })
      if(config.autoEnableFlash){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          self.setFlashState(true)
        }
      }
    } catch {
      self.scanResult(ScanResult.with {
        $0.type = .error
        $0.rawContent = "\(error)"
        $0.format = .unknown
      })
    }
  }

  @objc private func cancel() {
    scanResult( ScanResult.with {
      $0.type = .cancelled
      $0.format = .unknown
    });
  }

  @objc private func onToggleFlash() {
    setFlashState(!isFlashOn)
  }

  @objc private func switchCamera() {
      if (useCamera == -1 || useCamera == 0) {
          useCamera = 1
      }else if (useCamera == 1){
          useCamera = 0
      } else {
          useCamera = -1
      }
      viewDidAppear(true)
  }

  private func updateMenuButtons() {
    if config.strings["icon"] != "true" {
      let buttonText = isFlashOn ? config.strings["flash_off"] : config.strings["flash_on"]
      let btnFlash = UIBarButtonItem(title: buttonText, style: .plain, target: self, action: #selector(onToggleFlash))
      let btnSwitch = UIBarButtonItem(title: "Switch", style: .plain, target: self, action: #selector(switchCamera))

      self.navigationItem.setRightBarButtonItems([btnFlash, btnSwitch], animated: true)
    } else {
      let buttonFlash = UIButton(type: .custom)
      if isFlashOn {
          buttonFlash.setImage(UIImage(named: "ic_flash_off"), for: .normal)
      } else {
          buttonFlash.setImage(UIImage(named: "ic_flash_on"), for: .normal)
      }
      buttonFlash.addTarget(self, action: #selector(onToggleFlash), for: .touchUpInside)
      buttonFlash.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
      let barButtonFlash = UIBarButtonItem(customView: buttonFlash)

      let buttonSwitch = UIButton(type: .custom)
      buttonSwitch.setImage(UIImage(named: "ic_switch"), for: .normal)
      buttonSwitch.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
      buttonSwitch.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 2)
      let barButtonSwitch = UIBarButtonItem(customView: buttonSwitch)

      self.navigationItem.setRightBarButtonItems([barButtonSwitch, barButtonFlash], animated: true)
    }
  }
  
  private func setFlashState(_ on: Bool) {
    if let device = device {
      guard device.hasFlash && device.hasTorch else {
        return
      }
      
      do {
        try device.lockForConfiguration()
      } catch {
        return
      }
      
      device.flashMode = on ? .on : .off
      device.torchMode = on ? .on : .off
      
      device.unlockForConfiguration()
      updateMenuButtons()
    }
  }
  
  private func errorResult(errorCode: String){
    delegate?.didFailWithErrorCode(self, errorCode: errorCode)
    dismiss(animated: false)
  }
  
  private func scanResult(_ scanResult: ScanResult){
    self.delegate?.didScanBarcodeWithResult(self, scanResult: scanResult)
    dismiss(animated: false)
  }

  private func mapRestrictedBarcodeTypes() -> [String] {
    var types: [AVMetadataObject.ObjectType] = []

    config.restrictFormat.forEach({ format in
      if let mappedFormat = formatMap[format]{
        types.append(mappedFormat)
      }
    })

    return types.map({ t in t.rawValue})
  }

  private var cameraFromConfig: MTBCamera {
    return useCamera == 1 ? .front : .back
  }
}