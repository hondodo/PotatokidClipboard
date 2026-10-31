// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class CookieHelper {
  static String? getCookie(String name) {
    String? cookies = html.document.cookie;
    if (cookies == null) {
      return null;
    }
    List<String> cookieList = cookies.split(';');
    for (String cookie in cookieList) {
      String trimmedCookie = cookie.trim();
      if (trimmedCookie.startsWith('$name=')) {
        return trimmedCookie.split('=')[1];
      }
    }
    return null;
  }

  static void setCookie(String name, String value,
      {int? maxAge,
      String? path,
      String? domain,
      bool? secure,
      String? sameSite}) {
    String cookieString = '$name=$value';

    if (maxAge != null) {
      cookieString += '; max-age=$maxAge';
    }

    if (path != null) {
      cookieString += '; path=$path';
    }

    if (domain != null) {
      cookieString += '; domain=$domain';
    }

    if (secure == true) {
      cookieString += '; secure';
    }

    if (sameSite != null) {
      cookieString += '; samesite=$sameSite';
    }

    html.document.cookie = cookieString;
  }

  static void deleteCookie(String name) {
    html.document.cookie =
        '$name=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
  }
}
