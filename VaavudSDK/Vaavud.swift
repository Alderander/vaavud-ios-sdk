//
//  VaavudSDK.swift
//  Pods
//
//  Created by Andreas Okholm on 24/06/15.
//
//

import Foundation
import CoreMotion

public class VaavudSleipnirAvailability: NSObject {
    public class func available() -> Bool {
        return VaavudSDK.shared.sleipnirAvailable()
    }
}

public class VaavudSDK: WindListener, LocationListener,BluetoothListener {
    public static let shared = VaavudSDK()
    
    private var windController = WindController()
    private var locationController = LocationController()
    private var bluetoothController = BluetoothController()
    private var pressureController: CMAltimeter? = { return CMAltimeter.isRelativeAltitudeAvailable() ? CMAltimeter() : nil }()
    
    public private(set) var session = VaavudSession()
    
    
    public var windSpeedCallback: ((WindSpeedEvent) -> Void)?
    public var trueWindSpeedCallback: ((TrueWindSpeedEvent) -> Void)?
    public var windDirectionCallback: ((WindDirectionEvent) -> Void)?
    public var trueWindDirectionCallback: ((TrueWindDirectionEvent) -> Void)?
    public var bluetoothCallback: ((BluetoothEvent) -> Void)?
    public var bluetoothExtraCallback: ((BluetoothExtraEvent) -> Void)?
    
    
    public var pressureCallback: ((PressureEvent) -> Void)?
    public var headingCallback: ((HeadingEvent) -> Void)?
    public var locationCallback: ((LocationEvent) -> Void)?
    public var velocityCallback: ((VelocityEvent) -> Void)?
    public var altitudeCallback: ((AltitudeEvent) -> Void)?
    public var courseCallback: ((CourseEvent) -> Void)?
    
    
    private var lastDirection: WindDirectionEvent?
    private var lastSpeed: WindSpeedEvent?
    private var lastCourse: CourseEvent?
    private var lastVelocity: VelocityEvent?
    
    
    
    public var errorCallback: ((ErrorEvent) -> Void)?

    public var debugPlotCallback: (([[CGPoint]]) -> Void)?

    public init() {
        
        windController.addListener(listener: self)
        locationController.addListener(listener: windController)
        locationController.addListener(listener: self)
        bluetoothController.addListener(listener: self)
    }
    
    public func sleipnirAvailable() -> Bool {
        do { try locationController.start() }
        catch { return false }
        
        locationController.stop()
        
        do { try windController.start(flipped: false) }
        catch {
            return false
        }
        
        windController.stop()

        return true
    }
    
    
    func estimateTrueWind(time: Date) {
        
        let direction: Double? = lastDirection?.direction
        let speed: Double? = lastSpeed?.speed
        let course: Double? = lastCourse?.course
        let velocity: Double? = lastVelocity?.speed
        
        if let direction = direction, let speed = speed, let course = course, let velocity = velocity {

            let alpha = direction - course
            let rad = alpha * M_PI / 180.0 //Radias
            
            let trueSpeed = sqrt(pow(speed,2.0) + pow(velocity,2) - 2.0 * speed * velocity * Double(cos(rad)) )
            
            if (trueSpeed >= 0) && !trueSpeed.isNaN {
                let trueSpeedEvent = TrueWindSpeedEvent(time: time, speed: trueSpeed)
                trueWindSpeedCallback?(trueSpeedEvent)
            } else {
                let trueSpeedEvent = TrueWindSpeedEvent(time: time, speed: speed)
                trueWindSpeedCallback?(trueSpeedEvent)

            }
            
            var trueDirection: Double
            if(0 < rad && M_PI > rad) {
                let temp = ((speed * cos(rad)) - velocity) / trueSpeed
                trueDirection = acos(temp)
            }
            else{
                trueDirection = (-1) * acos(speed * Double(cos(rad)) - velocity / trueSpeed)
            }
            
            trueDirection = trueDirection * 180 / M_PI
            
            if (trueDirection != -1) && !trueDirection.isNaN {
                let directionEvent = TrueWindDirectionEvent(direction: trueDirection)
                trueWindDirectionCallback?(directionEvent)
            }
            
            if let _ = lastSpeed, let _ = lastDirection {
                session.addTrueWindDirection(event: TrueWindDirectionEvent(direction: trueDirection))
                session.addTrueWindSpeed(event: TrueWindSpeedEvent(time: time, speed: trueSpeed))
            }
            
        } else {
            if(speed != nil) {
                let trueSpeedEvent = TrueWindSpeedEvent(time: time, speed: speed!)
                trueWindSpeedCallback?(trueSpeedEvent)
                session.addTrueWindSpeed(event: trueSpeedEvent)
            }
        }
    }

    
    func reset() {
        session = VaavudSession()
    }
    
    
    public func startWithBluetooth(listener: IBluetoothManager) {
        reset()
        do {
            try locationController.start()
            bluetoothController.addBleListener(listener: listener)
            bluetoothController.start()
            startPressure()
        }
        catch {
            print("error")
        }
    }
    
        
    public func start(flipped: Bool) throws {
        reset()
        do {
            session.setWindMeter(isSleipnir: sleipnirAvailable())
            try locationController.start()
            try windController.start(flipped: flipped)
            startPressure()
            
        }
        catch {
//            newError(ErrorEvent(eventType: xx))
            throw error
        }
    }
    
    private func startPressure() {
        pressureController?.startRelativeAltitudeUpdates(to: .main) {
            altitudeData, error in
            if let kpa = altitudeData?.pressure.doubleValue {
                self.newPressure(event: PressureEvent(pressure: kpa*1000))
            }
            else {
                print("CMAltimeter error")
            }
        }
    }
    
    public func startLocationAndPressureOnly() throws {
        reset()
        try locationController.start()
        startPressure()
    }
    
    public func stop() {
        windController.stop()
        locationController.stop()
        bluetoothController.stop()
        pressureController?.stopRelativeAltitudeUpdates()
    }
    
    public func removeAllCallbacks() {
        windSpeedCallback = nil
        trueWindSpeedCallback = nil
        windDirectionCallback = nil
        trueWindDirectionCallback = nil
        bluetoothCallback = nil
        
        pressureCallback = nil
        headingCallback = nil
        locationCallback = nil
        velocityCallback = nil
        errorCallback = nil
    }
    
    public func resetWindDirectionCalibration() {
        windController.resetCalibration()
    }
    
    // MARK: Common error event handling
    
    func newError(event error: ErrorEvent) {
        errorCallback?(error)
    }
    
    // MARK: Pressure listener
    
    func newPressure(event: PressureEvent) {
        session.addPressure(event: event)
        pressureCallback?(event)
    }
    
    // MARK: Location listener

    func newHeading(event: HeadingEvent) {
        session.addHeading(event: event)
        headingCallback?(event)
    }
    
    func newLocation(event: LocationEvent) {
        session.addLocation(event: event)
        locationCallback?(event)
    }
    
    func newVelocity(event: VelocityEvent) {
        session.addVelocity(event: event)
        velocityCallback?(event)
        lastVelocity = event
    }
    
    func newCourse(event: CourseEvent) {
        session.addCourse(event: event)
        courseCallback?(event)
        lastCourse = event
    }
    
    func newAltitude(event: AltitudeEvent) {
        session.addAltitude(event: event)
        altitudeCallback?(event)
    }
    
    
    // MARK: bluetooth listener
    
    
    func newReading(event: BluetoothEvent) {
        let windSpeedE = WindSpeedEvent(speed: event.windSpeed)
        let windDirectionE = WindDirectionEvent(direction: Double(event.windDirection))
        
        session.addWindSpeed(event: windSpeedE)
        session.addWindDirection(event: windDirectionE)
        
        lastSpeed = windSpeedE
        lastDirection = windDirectionE
        
        estimateTrueWind(time: event.time)
        bluetoothCallback?(event)
    }
    
    
    func extraInfo(event: BluetoothExtraEvent) {
        bluetoothExtraCallback?(event)
    }

    
    
    // MARK: Wind listener
    
    public func newWindSpeed(event: WindSpeedEvent) {
        session.addWindSpeed(event: event)
        windSpeedCallback?(event)
        lastSpeed = event
        estimateTrueWind(time: event.time)
    }
    
    func newTrueWindWindSpeed(event: TrueWindSpeedEvent) {
        session.addTrueWindSpeed(event: event)
//        trueWindSpeedCallback?(event)
    }

    func newWindDirection(event: WindDirectionEvent) {
        session.addWindDirection(event: event)
        windDirectionCallback?(event)
        lastDirection = event
        if lastSpeed != nil {
            estimateTrueWind(time: lastSpeed!.time)
        }

    }
    
    func newTrueWindDirection(event: TrueWindDirectionEvent) {
        session.addTrueWindDirection(event: event)
//        trueWindDirectionCallback?(event)
    }
    
    func debugPlot(pointss valuess: [[CGPoint]]) {
        debugPlotCallback?(valuess)
    }
    
    deinit {
        print("DEINIT VaavudSDK")
    }
}

public struct VaavudSession {
    public let time = Date()
    
    public private(set) var meanDirection: Double?
    public private(set) var meanTrueDirection: Double?
    public private(set) var windSpeeds = [WindSpeedEvent]()
    public private(set) var trueWindSpeeds = [TrueWindSpeedEvent]()
    public private(set) var windDirections = [WindDirectionEvent]()
    public private(set) var trueWindDirections = [TrueWindDirectionEvent]()
    public private(set) var headings = [HeadingEvent]()
    public private(set) var locations = [LocationEvent]()
    public private(set) var velocities = [VelocityEvent]()
    public private(set) var temperatures = [TemperatureEvent]()
    public private(set) var pressures = [PressureEvent]()
    public private(set) var altitud = [AltitudeEvent]()
    public private(set) var course = [CourseEvent]()
    public private(set) var windMeter = "Sleipnir"
    
    public var meanSpeed: Double { return windSpeeds.count > 0 ? windSpeedSum/Double(windSpeeds.count) : 0 }
    public var meanTrueSpeed: Double { return trueWindSpeeds.count > 0 ? trueWindSpeedSum/Double(trueWindSpeeds.count) : 0 }

    public var maxSpeed: Double = 0
    public var trueMaxSpeed: Double = 0

    public var turbulence: Double? {
        return gustiness(speeds: windSpeeds.map { $0.speed })
//        return (windSpeedSquaredSum - windSpeedSum*windSpeedSum)/meanSpeed
    }
    
    // Private variables
    
    private var trueWindSpeedSum: Double = 0
    private var trueWindSpeedSquaredSum: Double = 0

    private var windSpeedSum: Double = 0
    private var windSpeedSquaredSum: Double = 0

    // Location data
    
    mutating func addHeading(event: HeadingEvent) {
        headings.append(event)
    }
    
    mutating func addLocation(event: LocationEvent) {
        locations.append(event)
    }

    mutating func addVelocity(event: VelocityEvent) {
        velocities.append(event)
    }
    
    mutating func addAltitude(event: AltitudeEvent) {
        altitud.append(event)
    }
    
    mutating func addCourse(event: CourseEvent) {
        course.append(event)
    }
    
    mutating func setWindMeter(isSleipnir: Bool){
        windMeter = isSleipnir ? "Sleipnir" : "Mjolnir"
    }
    
    

    // Wind data
    
    mutating func addWindSpeed(event: WindSpeedEvent) {
        windSpeeds.append(event)

        let speed = event.speed
        windSpeedSum += speed
        windSpeedSquaredSum += speed*speed
        maxSpeed = max(speed, maxSpeed)

        // Fixme: variable update frequency should be considered
    }
    
    mutating func addTrueWindSpeed(event: TrueWindSpeedEvent) {
        trueWindSpeeds.append(event)

        let speed = event.speed
        trueWindSpeedSum += speed
        trueWindSpeedSquaredSum += speed*speed
        trueMaxSpeed = max(speed, trueMaxSpeed)
    }
    
    mutating func addWindDirection(event: WindDirectionEvent) {
        meanDirection = mod(angle: event.direction)
        windDirections.append(event)
    }
    
    mutating func addTrueWindDirection(event: TrueWindDirectionEvent) {
        meanTrueDirection = mod(angle: event.direction)
        trueWindDirections.append(event)
    }
    
    // Temprature data

    mutating func addTemperature(event: TemperatureEvent) {
        temperatures.append(event)
    }
    
    // Pressure data

    mutating func addPressure(event: PressureEvent) {
        pressures.append(event)
    }
    
    // Helper function

    public func relativeTime(measurement: WindSpeedEvent) -> TimeInterval {
        return measurement.time.timeIntervalSince(time)
    }
    
    func description(measurement: WindSpeedEvent) -> String {
        return "WindSpeedEvent (time rel:" + String(format: "% 5.2f", relativeTime(measurement: measurement)) + " speed:" + String(format: "% 5.2f", measurement.speed) + " UnixTime: \(measurement.time.timeIntervalSince1970))"
    }
    
    
    public var dict: FirebaseDictionary {
        
        var session:FirebaseDictionary = [:]


        session["windMean"] = meanSpeed
        session["trueWindMean"] = meanTrueSpeed


        if let headings = headings.last {
            session["headings"] = headings.heading
        }
        
        if let location = locations.last {
            session["location"] = location.fireDict
        }
        
        if let velocity = velocities.last {
            session["velocity"] = velocity.speed
        }
        
        if let temperature = temperatures.last {
            session["temperature"] = temperature.temperature
        }
        
        if let pressure = pressures.last {
            session["pressure"] = pressure.pressure
        }
        
        if let altitude = altitud.last {
            session["altitude"] = altitude.altitude
        }
        
        if let course = course.last {
            session["course"] = course.course
        }
        
        
        session["timeStart"] = time.ms
        session["timeEnd"] = Date().ms
        session["windDirection"] = meanDirection
        if meanTrueDirection != nil && !meanTrueDirection!.isNaN {
            session["trueWindDirection"] = meanTrueDirection
        }
        session["windMeter"] = windMeter
        session["windMax"] = maxSpeed
        session["trueWindMax"] = trueMaxSpeed
        session["turbulence"] = turbulence
        
        return session
    }
}

func gustiness(speeds: [Double]) -> Double? {
    let n = Double(speeds.count)
    
    guard n > 0 else {
        return nil
    }

    let mean = speeds.reduce(0, +)/n
    let squares = speeds.map { ($0 - mean)*($0 - mean) }
    let variance = squares.reduce(0, +)/(n - 1)
    
//    let variance: Double = speeds.reduce(0) { $0 + ($1 - mean)*($1 - mean) }/(n - 1)
    
    return variance/mean
}




