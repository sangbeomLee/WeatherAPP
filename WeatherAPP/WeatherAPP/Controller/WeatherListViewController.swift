//
//  WeatherListViewController.swift
//  WeatherAPP
//
//  Created by hyeri kim on 31/07/2019.
//  Copyright © 2019 hyeri kim. All rights reserved.
//

import UIKit
import MapKit

class WeatherListViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    
    private let selectCity = Notification.Name(selectCityNotification)
    private let selectFahrenheitOrCelsius = Notification.Name(selectFahrenheitOrCelsiusNotification)
    private let locManager = CLLocationManager()
    private var currentLocation: CLLocation? 
    private var fahrenheitOrCelsius: FahrenheitOrCelsius? {
        didSet {
            DispatchQueue.main.async {
                print(self.fahrenheitOrCelsius)
                self.tableView.reloadData()
            } 
        }
    }
    private var myCities:[Coordinate] = [Coordinate]() {
        didSet {
            UserDefaults.standard.set(try? PropertyListEncoder().encode(myCities), forKey:"cities")
        }
    }
    private var weather:[WeatherInfo] = [WeatherInfo]() {
        didSet {
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }    
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        getCoordinate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewController()
        registerNib()
        createObserver()
        fetchCityList()
        fetchFahrenheitOrCelsius() 
    }
    
    private func fetchFahrenheitOrCelsius() {
        fahrenheitOrCelsius = FahrenheitOrCelsius(rawValue: UserInfo.fahrenheitOrCelsius())
        if let fahrenheit = fahrenheitOrCelsius {
            print(fahrenheit)
        }
    }
    
    private func fetchCityList() {
        guard let cities = UserInfo.getCityList() else {
            return
        }
        myCities = cities
        myCities.forEach({
            getWeatherByCoordinate(latitude: $0.lat, longitude: $0.lon)
        })
    }
    
    private func setupViewController() {
        tableView.delegate = self
        tableView.dataSource = self
        locManager.delegate = self
    }
    
    private func registerNib() {
        let weatherListCellNib = UINib(nibName: WeatherListTableViewCell.nibName, 
                                       bundle: nil
        )
        tableView.register(weatherListCellNib,
                           forCellReuseIdentifier: WeatherListTableViewCell.reuseIdentifier
        )
        
        let weatherListSettingCellNib = UINib(nibName: WeatherListSettingTableViewCell.nibName, 
                                              bundle: nil
        )
        tableView.register(weatherListSettingCellNib,
                           forCellReuseIdentifier: WeatherListSettingTableViewCell.reuseIdentifier
        )
    }
    
    private func createObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(selectedCity),
                                               name: selectCity, 
                                               object: nil
        )
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(selectedFahrenheitOrCelsius),
                                               name: selectFahrenheitOrCelsius,
                                               object: nil
        )
    }
    
    @objc private func selectedCity(notification: NSNotification) {
        guard let cityCoordinate = notification.object as? CLLocationCoordinate2D else {
            return
        }
        getWeatherByCoordinate(latitude: cityCoordinate.latitude,
                               longitude: cityCoordinate.longitude
        )
        myCities.append(Coordinate(lat: cityCoordinate.latitude, 
                                   lon: cityCoordinate.longitude)
        )
    }
    
    @objc private func selectedFahrenheitOrCelsius(notification: NSNotification) {
        fahrenheitOrCelsius = notification.object as? FahrenheitOrCelsius
    }
    
    private func getCoordinate() {
        locManager.requestWhenInUseAuthorization()  
    }
    
    private func getWeatherByCoordinate(latitude lat: Double, longitude lon: Double) {
        let parameters: [String: Any] = [
            "lat" : "\(lat)",
            "lon" : "\(lon)",
            "appid" : weatherAPIKey
        ]
        let weatherByCoordinatePath = "/data/2.5/weather"
        
        let request = APIRequest(method: .get,
                                 path: weatherByCoordinatePath,
                                 queryItems: parameters
        )
        
        APICenter().perform(urlString: BaseURL.weatherURL,
                            request: request
        ) { [weak self] (result) in
            guard let self = self else { 
                return
            }
            switch result {
            case .success(let response):        
                if let response = try? response.decode(to: WeatherInfo.self) {
                    self.checkCurrentLocationOrNot(bodyData: response.body)
                } else {
                    print(APIError.decodingFailed)
                }
            case .failure:
                print(APIError.networkFailed)
            }
        }
    }
    
    private func checkCurrentLocationOrNot(bodyData: WeatherInfo) {
        guard let coordinate = currentLocation?.coordinate else {
            return
        }
        if coordinate.latitude.makeRound() == bodyData.coord.lat,
            coordinate.longitude.makeRound() == bodyData.coord.lon {
            weather.insert(bodyData, at: 0)
        } else {
            weather.append(bodyData)
        }
    }
    
    private func getWeatherByCityName(name: String) {    
        let parameters: [String: Any] = [
            "q" : name,
            "appid" : weatherAPIKey
        ]
        
        let request = APIRequest(method: .get, queryItems: parameters)
        
        APICenter().perform(urlString: BaseURL.weatherURL, 
                            request: request
        ) { [weak self] (result) in
            guard let self = self else {
                return
            }
            switch result {
            case .success(let response):        
                if let response = try? response.decode(to: WeatherInfo.self) {
                    self.weather.append(response.body)
                }
            case .failure:
                print(APIError.networkFailed)
            }
        }
    }
}

// MARK: TableView Deleagate and DataSource
extension WeatherListViewController: UITableViewDelegate, UITableViewDataSource {   
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return weather.count 
        } else {
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cellType: WeatherList
        if indexPath.section == 1  {
            cellType = .Setting
        } else {
            cellType = .City
        }
        
        switch cellType {
        case .City:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: WeatherListTableViewCell.reuseIdentifier) as? WeatherListTableViewCell,
                let fahrenheitOrCelsius = fahrenheitOrCelsius else { 
                return UITableViewCell() 
            }
            cell.config(weatherData: (weather[indexPath.row]), cf: fahrenheitOrCelsius)
            return cell
        case .Setting:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: WeatherListSettingTableViewCell.reuseIdentifier) as? WeatherListSettingTableViewCell else { 
                return UITableViewCell() 
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let weatherData = weather[indexPath.row]
        DispatchQueue.main.async {
            let st = UIStoryboard.init(name: "CurrentWeather", bundle: nil)
            guard let vc = st.instantiateViewController(withIdentifier: "CurrentViewController") as? CurrentViewController else {
                return
            }
            vc.currentWeatherData = weatherData
            self.present(vc, animated: true, completion: nil)
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.row == 0 {
            return false
        } else {
            return true
        }
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            weather.remove(at: indexPath.row)
            myCities.remove(at: indexPath.row-1)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
}

// MARK: CLLocationManagerDelegate
extension WeatherListViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            guard let myCurrentLocation = locManager.location else {
                return
            }
            currentLocation = myCurrentLocation
            getWeatherByCoordinate(latitude: myCurrentLocation.coordinate.latitude,
                                   longitude: myCurrentLocation.coordinate.longitude
            )
        } else {
            print("user denied authorization")
        }
    }
}
