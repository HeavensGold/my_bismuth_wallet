// Package imports:
import 'package:event_taxi/event_taxi.dart';

// Project imports:
import 'package:my_bismuth_wallet/network/model/response/simple_price_response.dart';

class PriceEvent implements Event {
  final SimplePriceResponse? response;

  PriceEvent({this.response});
}
