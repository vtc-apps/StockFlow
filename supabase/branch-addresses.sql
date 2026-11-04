-- VTC PGIM · GST address of each branch (printed on GRN / transfer challans). Safe to run again.
update public.branches b
   set data = b.data || jsonb_build_object('address', v.a)
  from (values
    ('agr','Plot No 50, Avadhpuri Nagla, Albatiya, Agra, Agra, Uttar Pradesh, 282010'),
    ('ali','H. No. 222H-5, Lodhi Vihar Colony, Sasni Gate, Aligarh, Aligarh, Uttar Pradesh, 202001'),
    ('amr','R/o Moh Imli Wali Mandaiya, Pull ke pass, Amroha, Atrasi Road Hasanpur Bus stand, Amroha, Amroha, Uttar Pradesh, 244221'),
    ('bij','0, Taimur Deepa Rawli Road, Bijnor, Bijnor, Uttar Pradesh, 246701'),
    ('brt','AVAS VIKAS COLONY, NEAR PANI KI TANKI BARUT, BARUT, Baghpat, Uttar Pradesh, 250611'),
    ('bsr','H.NO. 281, SUSHILA VIHAR-II, NEAR PRADHAN FARM HOUSE, BULANDSHAHR, Bulandshahr, Uttar Pradesh, 203001'),
    ('cds','Bhawanipur Milak Maulagar, Radha Kishan Dharm shala, Chandausi, Sambhal, Uttar Pradesh, 244412'),
    ('chp','R/o Moh Patiyapada near Aashiyana colony Opp chandpur Petrol Pump, Haldaur Road, Chandpur Uttar Pardesh 246725'),
    ('dbi','Mohalla Mahadev, Galibpur Road, Debai, Bulandshahr, Uttar Pradesh, 203393'),
    ('dmp','SAKET VIHAR COLONY, NAGENA ROAD DHAMPUR, BIJNOR, Bijnor, Uttar Pradesh, 246761'),
    ('eta','31,, Aruna Nagar, Etah, Bijnor, Uttar Pradesh, 207001'),
    ('fzd','3/177 SHUAG NAGAR, INFRONT OF AVAS VIKAS OFFICE, FIROZABAD, Firozabad, Uttar Pradesh, 283203'),
    ('gra','H No 175, Jawhar Nagar W/No 9, Khad Gujar Road, Near Railway Station, Gajraula, Amroha, Uttar Pradesh, 244235'),
    ('gzb','Plot-A 10/15, Site-3 Industrial Area, Meerut Road, Ghaziabad, Ghaziabad, Uttar Pradesh, 201003'),
    ('hpr','Plot no 47 & 48, Jasrup nagar,Hapur, Uttar Pradesh 245101'),
    ('hts','52 A, ASHIRVAD DHAM, Hathras, Hathras, Uttar Pradesh, 204101'),
    ('jwr','Khasra No 488, Hamidpur Tappal Road, Near HP Petrol Pump, Hamidpur, Aligarh, Uttar Pradesh, 202165'),
    ('kos','CSRB Vidhya Ashram ke samne, Bharota Road Chaumuhan, Chaumuhan Rural, Mathura 281406'),
    ('krj','28, Nawal Vihar Murari Nagar, Khurja, Bulandshahr, Uttar Pradesh, 203131'),
    ('ksg','Ram Vatika Colony, Mamon, Kasganj, Uttar Pradesh 207123'),
    ('kth','HOUSE NO 397, SAINI NAGAR KHATULI MUZAFFARNAGAR, MUZAFFARNAGR, Muzaffarnagar, Uttar Pradesh, 251201'),
    ('lon','R/o A 13, Lal Bagh Colony, Loni, Ghaziabad, Uttar Pradesh, 201102'),
    ('mbd','H NO 7C/187 PHASE 2, AVAS VIKAS BUDHI VIHAR, Moradabad, Moradabad, Uttar Pradesh 244001'),
    ('mdn','T-12, Govindpuri,, Modinagar, Ghaziabad, Uttar Pradesh, 201204'),
    ('mrt','C 3, Dr Ram Manohar Lohia Nagar Pocket C, Meerut, Meerut, Uttar Pradesh, 250001'),
    ('mth','55-Rahul Enclave ,Nawda Road mathura Pin-281001'),
    ('mzn','184 GANDHI COLONY, GALI NO 17 OPPOSIT GANDHI VATIKA, MUZAFFARNAGAR, Muzaffarnagar, Uttar Pradesh, 251001'),
    ('njb','Khasra No 131, Bhagirath Puram Colony, Bashirpur, Najibabad, Bijnor, Uttar Pradesh 246763'),
    ('noi','D 118, HOSIREY COMPLEX PHASE II NOIDA, NOIDA, Gautam Buddha Nagar, Uttar Pradesh, 201305'),
    ('sbl','H.No.-187, Hallu Sarai, Sambhal, Sambhal, Uttar Pradesh, 244302'),
    ('sml','310, Near Kishan Dharamshala, Punjabi Colony, Railpar Kudana Road, Shamali, Shamli, Uttar Pradesh, 247776'),
    ('srp','9, Gandhi Nagar Nawada Road, Kailashpur, Saharanpur, Uttar Pradesh, 247001'),
    ('sya','H.No.-230, Chandpur Chungi, Yatharth Nurshing Home Wali Gali, Siyana, Bulandshahr, Uttar Pradesh, 245412'),
    ('tkd','Ward No. 6, Madarse Ke Pass, Nagaliya Road VIP Colony, Thakurdwara, Moradabad, Uttar Pradesh, 244601')
  ) v(u, a)
  join public.app_logins l on l.username = v.u
 where b.id = l.branch_id;
