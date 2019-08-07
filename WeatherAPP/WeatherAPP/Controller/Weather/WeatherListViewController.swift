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
    
    private let locManager: CLLocationManager = CLLocationManager()
    private let dispatchGroup: DispatchGroup = DispatchGroup()
    private var currentLocation: CLLocation?
    private var checkStatus: Bool = false
    private var weather:[WeatherInfo] = [WeatherInfo]() {
        didSet {
            DispatchQueue.main.async {
                self.tableView.reloadData()
            } 
        }
    }
    private var fahrenheitOrCelsius: FahrenheitOrCelsius? {
        didSet {
            DispatchQueue.main.async {
                self.tableView.reloadData()
            } 
        }
    }
    private var myCities: [Coordinate] = [Coordinate]() {
        didSet {
            UserDefaults.standard.set(try? PropertyListEncoder().encode(self.myCities),
                                      forKey:UserInfo.cities
            )
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self,
                                 action: #selector(refreshData),
                                 for: .valueChanged
        )
        refreshControl.tintColor = UIColor.black
        return refreshControl
    }()
    
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
        fahrenheitOrCelsius = FahrenheitOrCelsius(rawValue: UserInfo.getFahrenheitOrCelsius())
    }
    
    private func fetchCityList() {
        guard let cities = UserInfo.getCityList() else {
            return
        }
        myCities = cities
        DispatchQueue.global().async {
            self.myCities.forEach({
                self.getWeatherByCoordinate(latitude: $0.lat,
                                       longitude: $0.lon
                )
            })
        }
    }
    
    private func setupViewController() {
        tableView.addSubview(refreshControl)
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
                                               name: .selectCity, 
                                               object: nil
        )
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(selectedFahrenheitOrCelsius),
                                               name: .selectFahrenheitOrCelsius,
                                               object: nil
        )
    }
    
    @objc private func selectedCity(notification: NSNotification) {
        guard let cityCoordinate = notification.object as? CLLocationCoordinate2D else {
            return
        }
        if !myCities.contains(Coordinate(lat: cityCoordinate.latitude.makeRound(),
                                        lon: cityCoordinate.longitude.makeRound())){
            getWeatherByCoordinate(latitude: cityCoordinate.latitude,
                                   longitude: cityCoordinate.longitude
            )
            myCities.append(Coordinate(lat: cityCoordinate.latitude.makeRound(), 
                                       lon: cityCoordinate.longitude.makeRound())
            )
        }
    }
    
    @objc private func selectedFahrenheitOrCelsius(notification: NSNotification) {
        fahrenheitOrCelsius = notification.object as? FahrenheitOrCelsius
    }
    
    @objc private func refreshData() {
        guard let coordinate = currentLocation?.coordinate else {
            return
        }
        
        weather.removeAll()
        DispatchQueue.global().async {
            self.getWeatherByCoordinate(latitude: coordinate.latitude.makeRound(),
                                   longitude: coordinate.longitude.makeRound()
            )
            self.fetchCityList()
        }
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
        
        let request = APIRequest(method: .get,
                                 path: BasePath.list,
                                 queryItems: parameters
        )
        dispatchGroup.enter()
        APICenter().performSync(urlString: BaseURL.weatherURL,
                            request: request
        ) { [weak self] (result) in
            guard let self = self else { 
                return
            }
            switch result {
            case .success(let response):        
                if let response = try? response.decode(to: WeatherInfo.self) {
                    self.checkCurrentLocationOrNot(bodyData: response.body)
                    DispatchQueue.main.async {
                        self.refreshControl.endRefreshing()
                    }
                } else {
                    print(APIError.decodingFailed)
                }
            case .failure:
                print(APIError.networkFailed)
            }        
            self.dispatchGroup.leave()
        }
        dispatchGroup.notify(queue: .main) { 
            self.tableView.reloadData()
        }
    }
    
    private func checkCurrentLocationOrNot(bodyData: WeatherInfo) {
        guard let coordinate = currentLocation?.coordinate else {
            if !checkStatus {
                weather.append(bodyData)
            }
            return
        } 
        if bodyData.name == weather.first?.name {
            return
        }
        if coordinate.latitude.makeRound() == bodyData.coord.lat,
            coordinate.longitude.makeRound() == bodyData.coord.lon {
            weather.insert(bodyData, at: 0)
        } else {
            weather.append(bodyData)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: TableView Deleagate and DataSource
extension WeatherListViewController: UITableViewDelegate, UITableViewDataSource {   
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? weather.count : 1
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
            cell.config(weatherInfoData: weather[indexPath.row],
                        fahrenheitOrCelsius: fahrenheitOrCelsius
            )
            return cell
        case .Setting:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: WeatherListSettingTableViewCell.reuseIdentifier) as? WeatherListSettingTableViewCell else { 
                return UITableViewCell() 
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let st = UIStoryboard.init(name: "CurrentWeather", bundle: nil)
        guard let vc = st.instantiateViewController(withIdentifier: "PageViewController") as? PageViewController ,
            indexPath.section == 0 else {
            return
        }
        vc.weatherList = weather
        vc.startIndex = indexPath.row
        self.present(vc, animated: true, completion: nil)
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.row == 0 && checkStatus ? false : true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if !checkStatus {
                myCities.remove(at: indexPath.row)
                weather.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
            } else {
                let coordinate = weather[indexPath.row].coord
                myCities = myCities.filter { 
                    $0.lat.makeRound() != coordinate.lat && 
                        $0.lon.makeRound() != coordinate.lon 
                }
                weather.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
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
            getWeatherByCoordinate(latitude: myCurrentLocation.coordinate.latitude.makeRound(),
                                   longitude: myCurrentLocation.coordinate.longitude.makeRound()
            )
            checkStatus = true
        } else {
            print("user denied authorization")
        }
    }
}