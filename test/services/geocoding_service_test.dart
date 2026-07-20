import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/geocoding_service.dart';

void main() {
  group('AddressSuggestion.singleLineAddress', () {
    const ontarioRoadOnlyCases =
        <
          ({
            String typedQuery,
            String displayName,
            String street,
            String city,
            String postcode,
            String expected,
          })
        >[
          (
            typedQuery: '288 Bonis Ave',
            displayName:
                "Bonis Avenue, Tam O'Shanter-Sullivan, Scarborough-Agincourt, Scarborough, Toronto, Golden Horseshoe, Ontario, M1T 3L4, Canada",
            street: 'Bonis Avenue',
            city: 'Toronto',
            postcode: 'M1T 3L4',
            expected: '288 Bonis Avenue, Toronto, Ontario M1T 3L4',
          ),
          (
            typedQuery: '77 King St W',
            displayName:
                'King Street West, Financial District, Toronto, Golden Horseshoe, Ontario, M5H 1J9, Canada',
            street: 'King Street West',
            city: 'Toronto',
            postcode: 'M5H 1J9',
            expected: '77 King Street West, Toronto, Ontario M5H 1J9',
          ),
          (
            typedQuery: '100 Hurontario St',
            displayName:
                'Hurontario Street, Fairview, Mississauga, Peel Region, Golden Horseshoe, Ontario, L5B 3C1, Canada',
            street: 'Hurontario Street',
            city: 'Mississauga',
            postcode: 'L5B 3C1',
            expected: '100 Hurontario Street, Mississauga, Ontario L5B 3C1',
          ),
          (
            typedQuery: '200 Rideau St',
            displayName:
                'Rideau Street, ByWard Market, Ottawa, Eastern Ontario, Ontario, K1N 5X8, Canada',
            street: 'Rideau Street',
            city: 'Ottawa',
            postcode: 'K1N 5X8',
            expected: '200 Rideau Street, Ottawa, Ontario K1N 5X8',
          ),
          (
            typedQuery: '50 Main St E',
            displayName:
                'Main Street East, Corktown, Hamilton, Golden Horseshoe, Ontario, L8N 1G5, Canada',
            street: 'Main Street East',
            city: 'Hamilton',
            postcode: 'L8N 1G5',
            expected: '50 Main Street East, Hamilton, Ontario L8N 1G5',
          ),
          (
            typedQuery: '356 Wellington Rd S',
            displayName:
                'Wellington Road South, South London, London, Southwestern Ontario, Ontario, N6C 4P4, Canada',
            street: 'Wellington Road South',
            city: 'London',
            postcode: 'N6C 4P4',
            expected: '356 Wellington Road South, London, Ontario N6C 4P4',
          ),
          (
            typedQuery: '240 King St E',
            displayName:
                'King Street East, Downtown, Kitchener, Regional Municipality of Waterloo, Ontario, N2G 2L2, Canada',
            street: 'King Street East',
            city: 'Kitchener',
            postcode: 'N2G 2L2',
            expected: '240 King Street East, Kitchener, Ontario N2G 2L2',
          ),
          (
            typedQuery: '742 Ouellette Ave',
            displayName:
                'Ouellette Avenue, City Centre, Windsor, Essex County, Ontario, N9A 4J5, Canada',
            street: 'Ouellette Avenue',
            city: 'Windsor',
            postcode: 'N9A 4J5',
            expected: '742 Ouellette Avenue, Windsor, Ontario N9A 4J5',
          ),
          (
            typedQuery: '1380 Lasalle Blvd',
            displayName:
                'Lasalle Boulevard, New Sudbury, Greater Sudbury, Northeastern Ontario, Ontario, P3A 1W8, Canada',
            street: 'Lasalle Boulevard',
            city: 'Greater Sudbury',
            postcode: 'P3A 1W8',
            expected:
                '1380 Lasalle Boulevard, Greater Sudbury, Ontario P3A 1W8',
          ),
          (
            typedQuery: '221 Princess St',
            displayName:
                'Princess Street, Sydenham, Kingston, Frontenac County, Ontario, K7L 1A5, Canada',
            street: 'Princess Street',
            city: 'Kingston',
            postcode: 'K7L 1A5',
            expected: '221 Princess Street, Kingston, Ontario K7L 1A5',
          ),
        ];

    test('preserves typed house numbers for Ontario road-only matches', () {
      for (final testCase in ontarioRoadOnlyCases) {
        final suggestion = AddressSuggestion(
          displayName: testCase.displayName,
          latitude: 43.0,
          longitude: -79.0,
          street: testCase.street,
          city: testCase.city,
          state: 'Ontario',
          postcode: testCase.postcode,
        );

        expect(
          suggestion.singleLineAddress(typedQuery: testCase.typedQuery),
          testCase.expected,
        );
      }
    });

    test('keeps exact house matches unchanged', () {
      const suggestion = AddressSuggestion(
        displayName:
            '124, Bowles Drive, Riverside, Ajax, Durham Region, Golden Horseshoe, Ontario, L1T 4N1, Canada',
        latitude: 43.8635839,
        longitude: -79.0632063,
        street: '124 Bowles Drive',
        city: 'Ajax',
        state: 'Ontario',
        postcode: 'L1T 4N1',
      );

      expect(
        suggestion.singleLineAddress(typedQuery: '124 Bowles Drive'),
        '124 Bowles Drive, Ajax, Ontario L1T 4N1',
      );
    });
  });
}
