import 'dart:math';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class User {
  final String $id;
  final String $createdAt;
  final String $updatedAt;
  final String name;
  final String registration;
  final bool status;
  final List<String> labels;
  final String passwordUpdate;
  final String email;
  final String phone;
  final bool emailVerification;
  final bool phoneVerification;
  final String accessedAt;
  final Map<String, dynamic> prefs;
  final bool mfa;
  final List<dynamic> targets;

  User({
    required this.$id,
    required this.$createdAt,
    required this.$updatedAt,
    required this.name,
    required this.registration,
    required this.status,
    required this.labels,
    required this.passwordUpdate,
    required this.email,
    required this.phone,
    required this.emailVerification,
    required this.phoneVerification,
    required this.accessedAt,
    required this.prefs,
    required this.mfa,
    required this.targets,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      $id: map['\$id']?.toString() ?? '',
      $createdAt: map['\$createdAt']?.toString() ?? '',
      $updatedAt: map['\$updatedAt']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      registration: map['registration']?.toString() ?? '',
      status: map['status'] == true,
      labels: List<String>.from(map['labels'] ?? []),
      passwordUpdate: map['passwordUpdate']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      emailVerification: map['emailVerification'] == true,
      phoneVerification: map['phoneVerification'] == true,
      accessedAt: map['accessedAt']?.toString() ?? '',
      prefs: Map<String, dynamic>.from(map['prefs'] ?? {}),
      mfa: map['mfa'] == true,
      targets: List<dynamic>.from(map['targets'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '\$id': $id,
      '\$createdAt': $createdAt,
      '\$updatedAt': $updatedAt,
      'name': name,
      'registration': registration,
      'status': status,
      'labels': labels,
      'passwordUpdate': passwordUpdate,
      'email': email,
      'phone': phone,
      'emailVerification': emailVerification,
      'phoneVerification': phoneVerification,
      'accessedAt': accessedAt,
      'prefs': prefs,
      'mfa': mfa,
      'targets': targets,
    };
  }
}

class Session {
  final String $id;
  final String $createdAt;
  final String userId;
  final String expire;
  final String provider;
  final String providerUid;
  final String providerAccessToken;

  Session({
    required this.$id,
    required this.$createdAt,
    required this.userId,
    required this.expire,
    required this.provider,
    required this.providerUid,
    required this.providerAccessToken,
  });

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      $id: map['\$id']?.toString() ?? '',
      $createdAt: map['\$createdAt']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      expire: map['expire']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      providerUid: map['providerUid']?.toString() ?? '',
      providerAccessToken: map['providerAccessToken']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '\$id': $id,
      '\$createdAt': $createdAt,
      'userId': userId,
      'expire': expire,
      'provider': provider,
      'providerUid': providerUid,
      'providerAccessToken': providerAccessToken,
    };
  }
}

class Row {
  final String $id;
  final int $sequence;
  final String $tableId;
  final String $databaseId;
  final String $createdAt;
  final String $updatedAt;
  final List<String> $permissions;
  final Map<String, dynamic> data;

  Row({
    required this.$id,
    required this.$sequence,
    required this.$tableId,
    required this.$databaseId,
    required this.$createdAt,
    required this.$updatedAt,
    required this.$permissions,
    required this.data,
  });

  factory Row.fromMap(Map<String, dynamic> map) {
    return Row(
      $id: map['\$id']?.toString() ?? '',
      $sequence: map['\$sequence'] is int ? map['\$sequence'] as int : 0,
      $tableId: map['\$tableId']?.toString() ?? '',
      $databaseId: map['\$databaseId']?.toString() ?? '',
      $createdAt: map['\$createdAt']?.toString() ?? '',
      $updatedAt: map['\$updatedAt']?.toString() ?? '',
      $permissions: List<String>.from(map['\$permissions'] ?? []),
      data: Map<String, dynamic>.from(map['data'] ?? map),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '\$id': $id,
      '\$sequence': $sequence,
      '\$tableId': $tableId,
      '\$databaseId': $databaseId,
      '\$createdAt': $createdAt,
      '\$updatedAt': $updatedAt,
      '\$permissions': $permissions,
      'data': data,
    };
  }

  T convertTo<T>(T Function(Map<String, dynamic>) fromJson) => fromJson(data);
}

class RowList {
  final int total;
  final List<Row> rows;

  RowList({required this.total, required this.rows});

  factory RowList.fromMap(Map<String, dynamic> map) {
    final rowsList = (map['rows'] as List?) ?? [];
    return RowList(
      total: map['total'] is int ? map['total'] as int : rowsList.length,
      rows: rowsList.map((item) => Row.fromMap(Map<String, dynamic>.from(item))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'total': total,
      'rows': rows.map((r) => r.toMap()).toList(),
    };
  }
}

class Document extends Row {
  Document({
    required super.$id,
    required super.$sequence,
    required super.$tableId,
    required super.$databaseId,
    required super.$createdAt,
    required super.$updatedAt,
    required super.$permissions,
    required super.data,
  });

  factory Document.fromMap(Map<String, dynamic> map) {
    final row = Row.fromMap(map);
    return Document(
      $id: row.$id,
      $sequence: row.$sequence,
      $tableId: row.$tableId,
      $databaseId: row.$databaseId,
      $createdAt: row.$createdAt,
      $updatedAt: row.$updatedAt,
      $permissions: row.$permissions,
      data: row.data,
    );
  }
}

class Jwt {
  final String jwt;
  Jwt({required this.jwt});

  factory Jwt.fromMap(Map<String, dynamic> map) {
    return Jwt(jwt: map['jwt']?.toString() ?? '');
  }

  Map<String, dynamic> toMap() {
    return {'jwt': jwt};
  }
}

class ID {
  static String unique() {
    final Random random = Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        sb.write('-');
      }
      sb.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class Query {
  static String equal(String attribute, dynamic value) {
    if (value is List) {
      final listStr = value.map((v) => '"$v"').join(',');
      return 'equal("$attribute", [$listStr])';
    }
    return 'equal("$attribute", ["$value"])';
  }
  static String limit(int value) => 'limit($value)';
  static String orderDesc(String attribute) => 'orderDesc("$attribute")';
  static String orderAsc(String attribute) => 'orderAsc("$attribute")';
  static String cursorAfter(String value) => 'cursorAfter("$value")';
  static String greaterThanEqual(String attribute, dynamic value) => 'greaterThanEqual("$attribute", "$value")';
  static String lessThan(String attribute, dynamic value) => 'lessThan("$attribute", "$value")';
  static String search(String attribute, String value) => 'search("$attribute", "$value")';
}

class DatabaseException implements Exception {
  final String? message;
  final int? code;
  final String? type;
  final dynamic response;
  DatabaseException([this.message, this.code, this.type, this.response]);

  @override
  String toString() => 'DatabaseException: $message ($code, $type)';
}

class Client {
  Client setEndpoint(String endpoint) => this;
  Client setProject(String project) => this;
}

class Account {
  final dynamic _client;
  Account(this._client);

  Future<void> updatePushTarget({
    required String targetId,
    required String identifier,
  }) async {}
}

class Execution {
  final String responseBody;
  Execution({required this.responseBody});
}

class Functions {
  final dynamic _client;
  Functions(this._client);

  Future<Execution> createExecution({
    required String functionId,
    String? path,
    String? method,
    required String body,
  }) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        path ?? '',
        body: jsonDecode(body),
        headers: {
          'Content-Type': 'application/json',
        },
      );
      return Execution(responseBody: res.data?.toString() ?? '');
    } catch (e) {
      return Execution(responseBody: '');
    }
  }
}

class Storage {
  final dynamic _client;
  Storage(this._client);
}

class InputFile {
  static dynamic fromPath({required String path}) => null;
  static dynamic fromBytes({required List<int> bytes, required String filename}) => null;
}

class enums {
  static const ExecutionMethod = _ExecutionMethod();
}

class _ExecutionMethod {
  const _ExecutionMethod();
  final String pOST = 'POST';
  final String gET = 'GET';
}

class Role {
  static String any() => 'any';
  static String user(String id, [String? status]) => 'user:$id';
  static String users() => 'users';
}

class Permission {
  static String read(dynamic role) => 'read("$role")';
  static String write(dynamic role) => 'write("$role")';
  static String create(dynamic role) => 'create("$role")';
  static String update(dynamic role) => 'update("$role")';
  static String delete(dynamic role) => 'delete("$role")';
}

class Messaging {
  final dynamic _client;
  Messaging(this._client);

  Future<dynamic> createSubscriber({
    required String topicId,
    required String subscriberId,
    required String targetId,
  }) async {
    return null;
  }

  Future<dynamic> deleteSubscriber({
    required String topicId,
    required String subscriberId,
  }) async {
    return null;
  }
}

