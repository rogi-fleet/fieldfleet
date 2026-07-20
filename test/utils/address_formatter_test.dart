import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/address_formatter.dart';

void main() {
  group('AddressFormatter.condense', () {
    const ontarioRoadLevelCases = <({String input, String expected})>[
      (
        input:
            "Bonis Avenue, Tam O'Shanter-Sullivan, Scarborough-Agincourt, Scarborough, Toronto, Golden Horseshoe, Ontario, M1T 3L4, Canada",
        expected: 'Bonis Avenue, Toronto, Ontario M1T 3L4',
      ),
      (
        input:
            'King Street West, Financial District, Toronto, Golden Horseshoe, Ontario, M5H 1J9, Canada',
        expected: 'King Street West, Toronto, Ontario M5H 1J9',
      ),
      (
        input:
            'Hurontario Street, Fairview, Mississauga, Peel Region, Golden Horseshoe, Ontario, L5B 3C1, Canada',
        expected: 'Hurontario Street, Mississauga, Ontario L5B 3C1',
      ),
      (
        input:
            'Rideau Street, ByWard Market, Ottawa, Eastern Ontario, Ontario, K1N 5X8, Canada',
        expected: 'Rideau Street, Ottawa, Ontario K1N 5X8',
      ),
      (
        input:
            'Main Street East, Corktown, Hamilton, Golden Horseshoe, Ontario, L8N 1G5, Canada',
        expected: 'Main Street East, Hamilton, Ontario L8N 1G5',
      ),
      (
        input:
            'Wellington Road South, South London, London, Southwestern Ontario, Ontario, N6C 4P4, Canada',
        expected: 'Wellington Road South, London, Ontario N6C 4P4',
      ),
      (
        input:
            'King Street East, Downtown, Kitchener, Regional Municipality of Waterloo, Ontario, N2G 2L2, Canada',
        expected: 'King Street East, Kitchener, Ontario N2G 2L2',
      ),
      (
        input:
            'Ouellette Avenue, City Centre, Windsor, Essex County, Ontario, N9A 4J5, Canada',
        expected: 'Ouellette Avenue, Windsor, Ontario N9A 4J5',
      ),
      (
        input:
            'Lasalle Boulevard, New Sudbury, Greater Sudbury, Northeastern Ontario, Ontario, P3A 1W8, Canada',
        expected: 'Lasalle Boulevard, Greater Sudbury, Ontario P3A 1W8',
      ),
      (
        input:
            'Princess Street, Sydenham, Kingston, Frontenac County, Ontario, K7L 1A5, Canada',
        expected: 'Princess Street, Kingston, Ontario K7L 1A5',
      ),
    ];

    test(
      'joins split house number and street name from long geocoder results',
      () {
        const input =
            '124, Bowles Drive, Ajax, Durham Region, Golden Horseshoe, Ontario, L1T 4N1, Canada';

        expect(
          AddressFormatter.condense(input),
          '124 Bowles Drive, Ajax, Ontario L1T 4N1',
        );
      },
    );

    test('prefers numeric street parts over a leading place name', () {
      const input =
          'FieldFleet HQ, 124, Bowles Drive, Ajax, Durham Region, Golden Horseshoe, Ontario, L1T 4N1, Canada';

      expect(
        AddressFormatter.condense(input),
        '124 Bowles Drive, Ajax, Ontario L1T 4N1',
      );
    });

    test('keeps full first-line streets that are already intact', () {
      const input =
          '124 Bowles Drive, Ajax, Durham Region, Golden Horseshoe, Ontario, L1T 4N1, Canada';

      expect(
        AddressFormatter.condense(input),
        '124 Bowles Drive, Ajax, Ontario L1T 4N1',
      );
    });

    test('leaves already short addresses unchanged', () {
      const input = '124 Bowles Drive, Ajax, Ontario L1T 4N1';

      expect(AddressFormatter.condense(input), input);
    });

    test('keeps Ontario road-level matches on the street line', () {
      for (final testCase in ontarioRoadLevelCases) {
        expect(AddressFormatter.condense(testCase.input), testCase.expected);
      }
    });
  });
}
