import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/pve_api.dart';

// Generate a disposable self-signed, wrong-host certificate. No real server
// credentials or private keys are checked into the repository. Requires OpenSSL.
void main() {
  test(
    'TLS bypass is explicit, origin-scoped, isolated and never follows redirects',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'virthelm-tls-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final key = '${directory.path}/server.key';
      final cert = '${directory.path}/server.pem';
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        key,
        '-out',
        cert,
        '-subj',
        '/CN=not-the-server.invalid',
        '-days',
        '1',
      ]);
      expect(
        generated.exitCode,
        0,
        reason: 'Could not generate disposable TLS fixture',
      );
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      final foreignServer = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => foreignServer.close(force: true));
      var foreignRequests = 0;
      foreignServer.listen((request) {
        foreignRequests++;
        request.response.close();
      });
      final trap = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => trap.close(force: true));
      var redirectedRequests = 0;
      trap.listen((request) {
        redirectedRequests++;
        request.response.close();
      });
      var redirect = false;
      final authorizations = <String?>[];
      server.listen((request) {
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (redirect) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${trap.port}/stolen',
          );
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"data":{"version":"test"}}');
        }
        request.response.close();
      });
      final url = 'https://127.0.0.1:${server.port}';

      const credentials = ApiCredentials(
        tokenId: 'test@pve!test',
        secret: 'test-only',
      );
      final strictProfile = ConnectionProfile.create(
        name: 'Strict',
        address: url,
      );
      final strict = DioPveGateway(strictProfile, credentials);
      addTearDown(strict.close);
      await expectLater(strict.version(), throwsA(isA<PveFailure>()));
      expect(
        authorizations,
        isEmpty,
        reason: 'No token may reach an untrusted server by default',
      );

      final dio = Dio();
      final insecure = DioPveGateway(
        ConnectionProfile.create(
          name: 'Lab',
          address: url,
          allowInvalidCertificates: true,
        ),
        credentials,
        http: dio,
      );
      addTearDown(insecure.close);
      expect(await insecure.version(), 'test');
      expect(authorizations, [credentials.header]);
      final certificateFailure = throwsA(
        isA<PveFailure>().having(
          (error) => error.message,
          'message',
          contains('TLS certificate validation failed'),
        ),
      );
      // Even if the injected client's base URL changes, the TLS exception must
      // not extend to a different hostname or port.
      dio.options.baseUrl = 'https://localhost:${server.port}/api2/json';
      await expectLater(insecure.version(), certificateFailure);
      dio.options.baseUrl = 'https://127.0.0.1:${foreignServer.port}/api2/json';
      await expectLater(insecure.version(), certificateFailure);
      expect(foreignRequests, 0);
      expect(authorizations.length, 1);
      dio.options.baseUrl = '$url/api2/json';

      // A second default-strict client must remain strict after the opt-in client
      // has successfully connected to the very same origin.
      final other = DioPveGateway(strictProfile, credentials);
      addTearDown(other.close);
      await expectLater(other.version(), throwsA(isA<PveFailure>()));
      expect(authorizations.length, 1);
      redirect = true;
      await expectLater(insecure.version(), throwsA(isA<PveFailure>()));
      expect(redirectedRequests, 0);
      expect(dio.options.followRedirects, isFalse);
    },
  );
}
