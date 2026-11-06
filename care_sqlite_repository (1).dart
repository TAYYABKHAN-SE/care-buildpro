import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'care_data.dart';

class CareSqliteDatabase {
  CareSqliteDatabase._();
  static final CareSqliteDatabase instance = CareSqliteDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    final file = p.join(root, 'care_construction.db');
    _database = await openDatabase(
      file,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE records (
            collection TEXT NOT NULL,
            id TEXT NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (collection, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> saveRecord(
    String collection,
    String id,
    Map<String, dynamic> data, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await database;
    await db.insert(
      'records',
      {'collection': collection, 'id': id, 'data': jsonEncode(data)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getRecords(String collection) async {
    final db = await database;
    final rows = await db.query(
      'records',
      where: 'collection = ?',
      whereArgs: [collection],
      orderBy: 'rowid ASC',
    );
    return rows
        .map((row) => jsonDecode(row['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  Future<void> deleteRecord(String collection, String id) async {
    final db = await database;
    await db.delete(
      'records',
      where: 'collection = ? AND id = ?',
      whereArgs: [collection, id],
    );
  }
}

class SqliteCareRepository implements CareRepository {
  SqliteCareRepository() : _store = CareSqliteDatabase.instance;
  final CareSqliteDatabase _store;
  bool _seedChecked = false;
  static const _seedKey = 'demo_data_seeded_v1';

  Future<void> _ensureSeeded() async {
    if (_seedChecked) return;
    final db = await _store.database;
    final marker = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_seedKey],
      limit: 1,
    );

    if (marker.isEmpty) {
      // Reuse the exact demo records already defined in care_data.dart.
      final demo = DevelopmentCareRepository();
      final projects = await demo.getProjects();
      final entries = await demo.getFinancialEntries();

      await db.transaction((txn) async {
        for (final item in projects) {
          await _store.saveRecord('projects', item.id, _projectToMap(item), executor: txn);
        }
        for (final item in entries) {
          await _store.saveRecord('entries', item.id, _entryToMap(item), executor: txn);
        }
        await txn.insert(
          'settings',
          {'key': _seedKey, 'value': 'done'},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      });
    }
    _seedChecked = true;
  }

  Future<List<T>> _read<T>(
    String collection,
    T Function(Map<String, dynamic>) decode,
  ) async {
    await _ensureSeeded();
    return (await _store.getRecords(collection)).map(decode).toList(growable: false);
  }

  Future<void> _save(String collection, String id, Map<String, dynamic> data) async {
    await _ensureSeeded();
    await _store.saveRecord(collection, id, data);
  }

  @override
  Future<List<ConstructionProject>> getProjects() => _read('projects', _projectFromMap);
  @override
  Future<List<FinancialEntry>> getFinancialEntries() => _read('entries', _entryFromMap);
  @override
  Future<List<LabourRecord>> getLabour() => _read('labour', _labourFromMap);
  @override
  Future<List<AttendanceRecord>> getAttendance() => _read('attendance', _attendanceFromMap);
  @override
  Future<List<LabourPayrollSheet>> getLabourPayrollSheets() => _read('payroll', _payrollFromMap);
  @override
  Future<List<LabourPayment>> getLabourPayments() => _read('payments', _paymentFromMap);

  @override
  Future<void> saveProject(ConstructionProject project) =>
      _save('projects', project.id, _projectToMap(project));

  @override
  Future<void> deleteProject(String projectId) async {
    await _ensureSeeded();
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.delete('records', where: 'collection = ? AND id = ?', whereArgs: ['projects', projectId]);
      final rows = await txn.query('records', columns: ['id', 'data'], where: 'collection = ?', whereArgs: ['entries']);
      for (final row in rows) {
        final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        if (map['projectId'] == projectId) {
          await txn.delete('records', where: 'collection = ? AND id = ?', whereArgs: ['entries', row['id']]);
        }
      }
    });
  }

  @override
  Future<void> saveFinancialEntry(FinancialEntry entry) =>
      _save('entries', entry.id, _entryToMap(entry));
  @override
  Future<void> deleteFinancialEntry(String entryId) =>
      _store.deleteRecord('entries', entryId);
  @override
  Future<void> saveLabour(LabourRecord labour) =>
      _save('labour', labour.id, _labourToMap(labour));

  @override
  Future<void> archiveLabour(String labourId) async {
    final records = await getLabour();
    for (final labour in records.where((item) => item.id == labourId)) {
      await saveLabour(labour.copyWith(status: LabourStatus.archived));
    }
  }

  @override
  Future<void> deleteLabour(String labourId) =>
      _store.deleteRecord('labour', labourId);
  @override
  Future<void> saveAttendance(AttendanceRecord attendance) =>
      _save('attendance', attendance.id, _attendanceToMap(attendance));
  @override
  Future<void> deleteAttendance(String attendanceId) =>
      _store.deleteRecord('attendance', attendanceId);
  @override
  Future<void> saveLabourPayrollSheet(LabourPayrollSheet sheet) =>
      _save('payroll', sheet.id, _payrollToMap(sheet));

  @override
  Future<void> deleteLabourPayrollSheet(String sheetId) async {
    await _ensureSeeded();
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.delete('records', where: 'collection = ? AND id = ?', whereArgs: ['payroll', sheetId]);
      final rows = await txn.query('records', columns: ['id', 'data'], where: 'collection = ?', whereArgs: ['payments']);
      for (final row in rows) {
        final map = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        if (map['payrollSheetId'] == sheetId) {
          await txn.delete('records', where: 'collection = ? AND id = ?', whereArgs: ['payments', row['id']]);
        }
      }
    });
  }

  @override
  Future<void> saveLabourPayment(LabourPayment payment) =>
      _save('payments', payment.id, _paymentToMap(payment));
  @override
  Future<void> deleteLabourPayment(String paymentId) =>
      _store.deleteRecord('payments', paymentId);

  static Map<String, dynamic> _projectToMap(ConstructionProject x) => {
    'id': x.id, 'name': x.name, 'client': x.client, 'location': x.location,
    'status': x.status.name, 'startDate': x.startDate.toIso8601String(),
    'endDate': x.endDate.toIso8601String(), 'contractAmount': x.contractAmount,
    'estimatedBudget': x.estimatedBudget, 'progress': x.progress, 'archived': x.archived,
  };

  static ConstructionProject _projectFromMap(Map<String, dynamic> x) => ConstructionProject(
    id: x['id'] as String, name: x['name'] as String, client: x['client'] as String,
    location: x['location'] as String, status: ProjectStatus.values.byName(x['status'] as String),
    startDate: DateTime.parse(x['startDate'] as String), endDate: DateTime.parse(x['endDate'] as String),
    contractAmount: (x['contractAmount'] as num).toDouble(),
    estimatedBudget: (x['estimatedBudget'] as num).toDouble(),
    progress: (x['progress'] as num).toInt(), archived: x['archived'] as bool? ?? false,
  );

  static Map<String, dynamic> _entryToMap(FinancialEntry x) => {
    'id': x.id, 'projectId': x.projectId, 'type': x.type.name,
    'category': x.category, 'description': x.description, 'amount': x.amount,
    'date': x.date.toIso8601String(),
  };

  static FinancialEntry _entryFromMap(Map<String, dynamic> x) => FinancialEntry(
    id: x['id'] as String, projectId: x['projectId'] as String,
    type: FinancialEntryType.values.byName(x['type'] as String),
    category: x['category'] as String, description: x['description'] as String,
    amount: (x['amount'] as num).toDouble(), date: DateTime.parse(x['date'] as String),
  );

  static Map<String, dynamic> _labourToMap(LabourRecord x) => {
    'id': x.id, 'fullName': x.fullName, 'fatherName': x.fatherName, 'cnic': x.cnic,
    'phone': x.phone, 'address': x.address, 'trade': x.trade.name, 'dailyWage': x.dailyWage,
    'joiningDate': x.joiningDate.toIso8601String(), 'projectId': x.projectId,
    'status': x.status.name, 'photoUrl': x.photoUrl,
  };

  static LabourRecord _labourFromMap(Map<String, dynamic> x) => LabourRecord(
    id: x['id'] as String, fullName: x['fullName'] as String, fatherName: x['fatherName'] as String,
    cnic: x['cnic'] as String, phone: x['phone'] as String, address: x['address'] as String,
    trade: LabourTrade.values.byName(x['trade'] as String), dailyWage: (x['dailyWage'] as num).toDouble(),
    joiningDate: DateTime.parse(x['joiningDate'] as String), projectId: x['projectId'] as String,
    status: LabourStatus.values.byName(x['status'] as String), photoUrl: x['photoUrl'] as String?,
  );

  static Map<String, dynamic> _attendanceToMap(AttendanceRecord x) => {
    'id': x.id, 'labourId': x.labourId, 'projectId': x.projectId,
    'date': x.date.toIso8601String(), 'inTimeMinutes': x.inTimeMinutes,
    'outTimeMinutes': x.outTimeMinutes, 'status': x.status.name,
    'dailyWage': x.dailyWage, 'remarks': x.remarks,
  };

  static AttendanceRecord _attendanceFromMap(Map<String, dynamic> x) => AttendanceRecord(
    id: x['id'] as String, labourId: x['labourId'] as String, projectId: x['projectId'] as String,
    date: DateTime.parse(x['date'] as String), inTimeMinutes: (x['inTimeMinutes'] as num?)?.toInt(),
    outTimeMinutes: (x['outTimeMinutes'] as num?)?.toInt(),
    status: AttendanceStatus.values.byName(x['status'] as String),
    dailyWage: (x['dailyWage'] as num).toDouble(), remarks: x['remarks'] as String? ?? '',
  );

  static Map<String, dynamic> _payrollToMap(LabourPayrollSheet x) => {
    'id': x.id, 'labourId': x.labourId, 'projectId': x.projectId, 'year': x.year,
    'month': x.month, 'overtimeHours': x.overtimeHours, 'overtimeRate': x.overtimeRate,
    'advance': x.advance, 'deductions': x.deductions, 'notes': x.notes,
  };

  static LabourPayrollSheet _payrollFromMap(Map<String, dynamic> x) => LabourPayrollSheet(
    id: x['id'] as String, labourId: x['labourId'] as String, projectId: x['projectId'] as String,
    year: (x['year'] as num).toInt(), month: (x['month'] as num).toInt(),
    overtimeHours: (x['overtimeHours'] as num).toDouble(), overtimeRate: (x['overtimeRate'] as num).toDouble(),
    advance: (x['advance'] as num).toDouble(), deductions: (x['deductions'] as num).toDouble(),
    notes: x['notes'] as String? ?? '',
  );

  static Map<String, dynamic> _paymentToMap(LabourPayment x) => {
    'id': x.id, 'payrollSheetId': x.payrollSheetId, 'amount': x.amount,
    'date': x.date.toIso8601String(), 'reference': x.reference, 'remarks': x.remarks,
  };

  static LabourPayment _paymentFromMap(Map<String, dynamic> x) => LabourPayment(
    id: x['id'] as String, payrollSheetId: x['payrollSheetId'] as String,
    amount: (x['amount'] as num).toDouble(), date: DateTime.parse(x['date'] as String),
    reference: x['reference'] as String? ?? '', remarks: x['remarks'] as String? ?? '',
  );
}
