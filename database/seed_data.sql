-- ============================================================
-- KLNCE Smart Transport System — Seed Data
-- K.L.N. College of Engineering & Arts and Sciences College
-- Character set: UTF8MB4 (supports Tamil script)
-- ============================================================

USE klnce_transport;

-- ------------------------------------------------------------
-- No demo users are seeded. Create or update an administrator securely with
-- backend/set_admin_credentials.py after configuring backend/.env.

-- ------------------------------------------------------------
-- 1. Master Stops Catalog (All 48 Madurai area bus stops)
-- Extracted from KLNCE actual transport route schedules
-- ------------------------------------------------------------
INSERT INTO master_stops (id, standard_name_en, standard_name_ta, aliases, latitude, longitude) VALUES
(1, 'Thirunagar', 'திருநகர்', '["Thirunagar", "திருநகர்", "Thiru Nagar", "TN"]', 9.8762, 78.0772),
(2, 'Thiruparankundram', 'திருப்பரங்குன்றம்', '["TPK", "Thiruparankundram", "திருப்பரங்குன்றம்", "TPK Police Station", "TPK Amman Kovil"]', 9.8828, 78.0722),
(3, 'Moolakarai', 'மூலக்கரை', '["Moolakarai", "மூலக்கரை"]', 9.8911, 78.0825),
(4, 'Pasumalai', 'பசுமலை', '["Pasumalai", "பசுமலை"]', 9.9023, 78.0931),
(5, 'Pykara', 'பைக்கரா', '["Pykara", "பைக்கரா"]', 9.9090, 78.0980),
(6, 'Alagappan Nagar', 'அழகப்பன் நகர்', '["Alagappan Nagar", "அழகப்பன் நகர்"]', 9.9140, 78.1020),
(7, 'Palanganatham', 'பழங்கானத்தம்', '["Palanganatham", "பழங்கானத்தம்"]', 9.9180, 78.1060),
(8, 'TVS Park', 'TVS பூங்கா', '["TVS Park", "TVS பூங்கா", "TVS Nagar School"]', 9.9195, 78.1090),
(9, 'Jeeva Nagar', 'ஜீவா நகர்', '["Jeeva Nagar", "ஜீவா நகர்"]', 9.9210, 78.1120),
(10, 'Mahal', 'மஹால்', '["Mahal", "மஹால்", "Thirumalai Nayakkar Mahal"]', 9.9152, 78.1235),
(11, 'SVN College', 'SVN காலேஜ்', '["SVN College", "SVN காலேஜ்", "நாச்சிகுளம்", "SVN"]', 9.9320, 78.0510),
(12, 'Achampathu', 'அச்சம்பத்து', '["Achampathu", "அச்சம்பத்து"]', 9.9360, 78.0620),
(13, 'Virattipathu', 'விராட்டிபத்து', '["Virattipathu", "விராட்டிபத்து"]', 9.9390, 78.0750),
(14, 'Kochadai', 'கோச்சடை', '["Kochadai", "கோச்சடை"]', 9.9410, 78.0920),
(15, 'Mudakkusalai', 'முடக்குச்சாலை', '["Mudakkusalai", "முடக்குச்சாலை"]', 9.9380, 78.0980),
(16, 'PP Chavadi', 'PPசாவடி', '["PP Chavadi", "PPசாவடி"]', 9.9340, 78.1030),
(17, 'South Gate', 'தெற்குவாசல்', '["South Gate", "தெற்குவாசல்", "Therkuvasal"]', 9.9130, 78.1180),
(18, 'Kalavasal', 'காளைவாசல்', '["Kalavasal", "காளைவாசல்", "BigBazaar", "காளைவாசல்(BigBazaar)"]', 9.9360, 78.1000),
(19, 'Chokkalinganagar', 'சொக்கலிங்கநகர்', '["Chokkalinganagar", "சொக்கலிங்கநகர்"]', 9.9320, 78.1050),
(20, 'Ponmeni', 'பொன்மேனி', '["Ponmeni", "பொன்மேனி"]', 9.9290, 78.1030),
(21, 'Ram Nagar', 'ராம்நகர்', '["Ram Nagar", "ராம்நகர்"]', 9.9270, 78.1060),
(22, 'Ellisnagar', 'எல்லிஸ்நகர்', '["Ellisnagar", "Ellisnagar(Out)", "எல்லிஸ்நகர்"]', 9.9210, 78.1100),
(23, 'Periyar Bus Stand', 'பெரியார்', '["Periyar", "பெரியார்", "Periyar Bus Stand", "ZamZam"]', 9.9170, 78.1140),
(24, 'Vilakkuthoon', 'விளக்குத்தூண்', '["Vilakkuthoon", "விளக்குத்தூண்", "விளாம்பீச்ராவ்"]', 9.9160, 78.1210),
(25, 'Vasantha Nagar', 'வசந்தநகர்', '["Vasantha Nagar", "வசந்தநகர்"]', 9.9080, 78.1090),
(26, 'Andalpuram', 'ஆண்டாள்புரம்', '["Andalpuram", "ஆண்டாள்புரம்"]', 9.9050, 78.1110),
(27, 'Sappani Kovil', 'சப்பானிகோவில்', '["Sappani Kovil", "சப்பானிகோவில்"]', 9.9120, 78.1160),
(28, 'Thavittuchanthai', 'தவிட்டுச்சந்தை', '["Thavittuchanthai", "தவிட்டுச்சந்தை"]', 9.9140, 78.1200),
(29, 'Sikkandar Chavadi', 'சிக்கந்தர் சாவடி', '["Sikkandar Chavadi", "Sikkandar Chavadi"]', 9.9650, 78.1100),
(30, 'Dinamani Nagar', 'தினமணி நகர்', '["Dinamani nagar", "Dinamani Nagar"]', 9.9600, 78.1140),
(31, 'Koodal Nagar', 'கூடல் நகர்', '["Koodal Nagar", "கூடல் நகர்"]', 9.9540, 78.1170),
(32, 'Anjal Nagar', 'அஞ்சல்நகர்', '["Anjal Nagar", "அஞ்சல்நகர்"]', 9.9480, 78.1190),
(33, 'Santhi Nagar', 'சாந்திநகர்', '["Santhi Nagar", "சாந்திநகர்"]', 9.9440, 78.1210),
(34, 'Simmakkal', 'சிம்மக்கல்', '["Simmakkal", "சிம்மக்கல்", "Simmakkal(5)"]', 9.9260, 78.1220),
(35, 'Goripalayam', 'கோரிப்பாளையம்', '["Goripalayam", "கோரிப்பாளையம்", "Govt Hospital"]', 9.9310, 78.1270),
(36, 'Nellpettai', 'நெல்பேட்டை', '["Nellpettai", "நெல்பேட்டை", "Nelpettai"]', 9.9240, 78.1250),
(37, 'Teppakulam', 'தெப்பக்குளம்', '["Teppakulam", "தெப்பக்குளம்", "Teppakulam Checkpost", "தெப்பக்குளம்செக்போஸ்ட்"]', 9.9160, 78.1480),
(38, 'Sandapattai', 'சண்டாப்பேட்டை', '["Sandapattai", "சண்டாப்பேட்டை"]', 9.9200, 78.1380),
(39, 'Park Town', 'பார்க் டவுன்', '["Park Town", "Park Town, P&T நகர்", "P&T Nagar"]', 9.9550, 78.1320),
(40, 'BB Kulam', 'BB குளம்', '["BB Kulam", "BBகுளம்", "BBகுளம்(3)", "BB Kulam Outpost"]', 9.9420, 78.1300),
(41, 'Tallakulam', 'தல்லாகுளம்', '["Tallakulam", "தல்லாகுளம்", "Tallakulam Perumal Kovil"]', 9.9350, 78.1310),
(42, 'Chokkikulam', 'சொக்கிகுளம்', '["Chokkikulam", "சொக்கிகுளம்", "CEOA", "CEOA பள்ளி"]', 9.9380, 78.1350),
(43, 'Othakadai', 'ஒத்தக்கடை', '["Othakadai", "ஒத்தக்கடை"]', 9.9650, 78.1920),
(44, 'Surya Nagar', 'சூர்யாநகர்', '["Surya Nagar", "சூர்யாநகர்"]', 9.9580, 78.1680),
(45, 'Surveyor Colony', 'சர்வேயர்காலனி', '["Surveyor Colony", "சர்வேயர்காலனி"]', 9.9520, 78.1610),
(46, 'Viraganur Ring Road', 'விரகனூர் ரிங்ரோடு', '["Viraganur Ring Road", "விரகனூர்ரிங්රோடு", "Viraganur"]', 9.9050, 78.1620),
(47, 'Silaiman', 'சிலைமான்', '["Silaiman", "சிலைமான்", "LKT Nagar", "LKT நகர்"]', 9.8920, 78.1880),
(48, 'KLNCE Campus Pottapalayam', 'கே.எல்.என்.சி.இ. வளாகம்', '["KLNCE Campus", "College", "Pottapalayam", "KLN Arts"]', 9.8820, 78.0802)
ON DUPLICATE KEY UPDATE standard_name_en=VALUES(standard_name_en);

-- ------------------------------------------------------------
-- 3. Published Schedule: Nov 10 Incoming Trip
-- Represents the real uploaded document for KLN Engineering & Arts
-- ------------------------------------------------------------
INSERT INTO schedule_documents (
  id, title, file_url, file_type, trip_direction, college, effective_date, status, created_by, verified_by, verified_at, published_at
) VALUES (
  1,
  'College Bus Route Schedule for Staff & Student - Incoming',
  'https://storage.googleapis.com/klnce-transport/schedules/nov10_incoming.jpg',
  'image',
  'incoming',
  'both',
  '2026-11-10',
  'published',
  1,
  1,
  '2026-11-09 18:00:00',
  '2026-11-09 18:05:00'
) ON DUPLICATE KEY UPDATE status=VALUES(status);

-- ------------------------------------------------------------
-- 4. Bus Routes (Engineering College: 29 routes + Arts: IT9)
-- ------------------------------------------------------------
INSERT INTO bus_routes (id, schedule_id, bus_code, route_display_name, departure_time, college, display_order) VALUES
(1, 1, 'K', 'Thirunagar to KLNCE Campus', '08:00', 'engineering', 1),
(2, 1, 'I1', 'TPK to KLNCE Campus', '08:00', 'engineering', 2),
(3, 1, 'E', 'Alagappan Nagar to Mahal to KLNCE', '08:05', 'engineering', 3),
(4, 1, 'J1', 'SVN College to TVS to KLNCE', '07:50', 'engineering', 4),
(5, 1, 'D1', 'Kochadai to South Gate to KLNCE', '08:05', 'engineering', 5),
(6, 1, 'T1', 'Kalavasal(BigBazaar) to Ellisnagar to KLNCE', '08:00', 'engineering', 6),
(7, 1, 'J', 'Vasantha Nagar to Mahal to KLNCE', '08:10', 'engineering', 7),
(8, 1, 'V1', 'Sikkandar Chavadi to Koodal Nagar to KLNCE', '08:05', 'engineering', 8),
(9, 1, 'R1', 'Alagumalai to Simmakkal(5) to KLNCE', '08:05', 'engineering', 9),
(10, 1, 'Q1', 'Theppakulam to Nelpettai to KLNCE', '08:05', 'engineering', 10),
(11, 1, 'D', 'District Court to Avaniyapuram to KLNCE', '08:05', 'engineering', 11),
(12, 1, 'F', 'MMC Colony to Fathima College to KLNCE', '08:05', 'engineering', 12),
(13, 1, 'Y6', 'Meenakshi Nagar to Villapuram to KLNCE', '08:05', 'engineering', 13),
(14, 1, 'M1', 'Kaliamman Kovil to Chinthamani to KLNCE', '08:10', 'engineering', 14),
(15, 1, 'H', 'Mahal Direct to KLNCE', '08:10', 'engineering', 15),
(16, 1, 'C', 'Keelavasal to Thiagarajar College to KLNCE', '08:10', 'engineering', 16),
(17, 1, 'V', 'Munichalai to Teppakulam to Viraganur', '08:10', 'engineering', 17),
(18, 1, 'M', 'Sandapattai to Teppakulam to KLNCE', '08:10', 'engineering', 18),
(19, 1, 'S1', 'Park Town to BB Kulam to Teppakulam', '08:05', 'engineering', 19),
(20, 1, 'Z', 'Tallakulam Perumal Kovil to Anna Nilayam', '08:10', 'engineering', 20),
(21, 1, 'B1', 'Alagarkovil to CEOA to MG Nagar', '08:05', 'engineering', 21),
(22, 1, 'F1', 'Yadavar College to Thiruppalai to DRO', '08:05', 'engineering', 22),
(23, 1, 'G1', 'Othakadai to Mahatma School to Viraganur', '08:05', 'engineering', 23),
(24, 1, 'E1', 'Police Station to Ring Road to KLNCE', '08:05', 'engineering', 24),
(25, 1, 'R', 'Moondrumavadi to Alagar Nagar to KLNCE', '08:05', 'engineering', 25),
(26, 1, 'C1', 'KK Nagar to Melamadai to KLNCE', '08:15', 'engineering', 26),
(27, 1, 'K1', 'Vandiyur to KLNCE Campus', '08:15', 'engineering', 27),
(28, 1, 'G', 'Thirupuvanam to Silaiman to LKT Nagar', '08:10', 'engineering', 28),
(29, 1, 'W1', 'Sivagangai Direct to KLNCE', '07:35', 'engineering', 29),
(30, 1, 'IT9', 'Arts & Science: TPK to Teppakulam to KLNCE', '07:50', 'arts_science', 30)
ON DUPLICATE KEY UPDATE departure_time=VALUES(departure_time);

-- ------------------------------------------------------------
-- 5. Route Stops Mapping
-- ------------------------------------------------------------
-- Bus K (Thirunagar Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(1, 1, 'Thirunagar 8, 7, 6, 5, 4, 3, 2, 1 curve', 'திருநகர் 8, 7, 6, 5, 4, 3, 2, 1வளைவு', '08:00', 1),
(1, 2, 'Harvey Patti', 'ஹார்விபட்டி', '08:05', 2),
(1, 3, 'TPK Park Moolakarai', 'TPK பூங்கா மூலக்கரை', '08:12', 3),
(1, 4, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:40', 48);

-- Bus I1 (TPK & Pasumalai Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(2, 1, 'TPK Amman Kovil', 'TPK அம்மன் கோவில்', '08:00', 2),
(2, 2, 'TPK Police Station', 'TPK போலீஸ் ஸ்டேஷன்', '08:03', 2),
(2, 3, 'Pasumalai', 'பசுமலை', '08:08', 4),
(2, 4, 'Pykara', 'பைக்கரா', '08:12', 5),
(2, 5, 'Alagappan Nagar', 'அழகப்பன் நகர்', '08:16', 6),
(2, 6, 'Palanganatham', 'பழங்கானத்தம்', '08:20', 7),
(2, 7, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:45', 48);

-- Bus T1 (Kalavasal & Ellisnagar Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(6, 1, 'Kalavasal(BigBazaar)', 'காளைவாசல்(BigBazaar)', '08:00', 18),
(6, 2, 'Chokkalinganagar', 'சொக்கலிங்கநகர்', '08:04', 19),
(6, 3, 'Ponmeni', 'பொன்மேனி', '08:08', 20),
(6, 4, 'Ram Nagar', 'ராம்நகர்', '08:12', 21),
(6, 5, 'Ellisnagar(Out)', 'Ellisnagar(Out)', '08:16', 22),
(6, 6, 'Periyar', 'பெரியார்', '08:22', 23),
(6, 7, 'Vilakkuthoon', 'விளாம்பீச்ராவ்', '08:28', 24),
(6, 8, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:45', 48);

-- Bus M (Sandapattai & Teppakulam Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(18, 1, 'Sandapattai', 'Sandapattai', '08:10', 38),
(18, 2, 'Nirmala School', 'நிர்மலா ஸ்கூல்', '08:13', 38),
(18, 3, 'Aduppukootu', 'அடுப்பாரை', '08:16', 38),
(18, 4, 'Pandian Nagar', 'பாண்டியன் நகர்', '08:20', 38),
(18, 5, 'Teppakulam Checkpost', 'தெப்பக்குளம் செக்போஸ்ட்', '08:25', 37),
(18, 6, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:45', 48);

-- Bus S1 (Park Town to Teppakulam)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(19, 1, 'Park Town', 'Park Town', '08:05', 39),
(19, 2, 'P&T Nagar', 'P&T நகர்', '08:08', 39),
(19, 3, 'BB Kulam(3)', 'BBகுளம்(3)', '08:14', 40),
(19, 4, 'KP Kovil Outpost', 'KP கோவில் அவுட்போஸ்ட்', '08:20', 40),
(19, 5, 'Tallakulam Perumal Kovil', 'Tallakulam Perumal Kovil', '08:25', 41),
(19, 6, 'Teppakulam Checkpost', 'தெப்பக்குளம் செக்போஸ்ட்', '08:32', 37),
(19, 7, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:50', 48);

-- Bus G1 (Othakadai to Mahatma School Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(23, 1, 'Othakadai', 'ஒத்தக்கடை', '08:05', 43),
(23, 2, 'Surya Nagar', 'சூர்யாநகர்', '08:10', 44),
(23, 3, 'Surveyor Colony', 'சர்வேயர்காலனி', '08:15', 45),
(23, 4, 'Mahatma School', 'Mahatma School', '08:20', 45),
(23, 5, 'Prithi Hospital', 'Prithi Hospital', '08:24', 45),
(23, 6, 'Viraganur Ring Road', 'விரகனூர்ரிங්රோடு', '08:32', 46),
(23, 7, 'KLNCE Campus', 'கே.எல்.என்.சி.இ. வளாகம்', '08:45', 48);

-- Bus IT9 (KLN Arts & Sciences College Route)
INSERT INTO route_stops (bus_route_id, stop_order, stop_name_en, stop_name_ta, estimated_arrival_time, master_stop_id) VALUES
(30, 1, 'TPK Park', 'TPK பூங்கா', '07:50', 2),
(30, 2, 'TPK Police Station', 'TPK போலீஸ்ஸ்டேஷன்', '07:53', 2),
(30, 3, 'Moolakarai', 'மூலக்கரை', '07:56', 3),
(30, 4, 'Pasumalai', 'பசுமலை', '08:00', 4),
(30, 5, 'Periyar (ZamZam)', 'பெரியார்(ZamZam)', '08:15', 23),
(30, 6, 'Avaniyapuram Bus Stand', 'அவனியாபுரம்(Bus Stand)', '08:22', 11),
(30, 7, 'Teppakulam Checkpost', 'தெப்பக்குளம்செக்போஸ்ட்', '08:33', 37),
(30, 8, 'Viraganur Ring Road', 'விரகனூர்ரிங්රோடு', '08:38', 46),
(30, 9, 'KLN Arts & Science College', 'கே.எல்.என். கலை மற்றும் அறிவியல் கல்லூரி', '08:45', 48);

-- ------------------------------------------------------------
-- 6. Initial Active GPS location for demonstration
-- ------------------------------------------------------------
INSERT INTO gps_locations (bus_code, driver_id, latitude, longitude, speed_kmh, is_active_trip, recorded_at) VALUES
('K', 2, 9.8762, 78.0772, 32.5, TRUE, NOW()),
('M', 2, 9.9160, 78.1480, 28.0, TRUE, NOW()),
('IT9', 2, 9.9170, 78.1140, 30.2, TRUE, NOW());

-- ============================================================
-- End of seed_data.sql
-- ============================================================

