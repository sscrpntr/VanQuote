require "application_system_test_case"

class RegistrationAndLocaleTest < ApplicationSystemTestCase
  test "optional communications checkbox does not block accepting pending terms" do
    visit new_registration_path
    form = find("form[data-controller='registration-consent']")
    page.execute_script(
      "arguments[0].setAttribute('data-registration-consent-require-communications-value', 'false')",
      form
    )

    find("#user_accept_terms").check

    assert_button "Crear cuenta", disabled: false
    assert_not find("#user_accept_operational_email").checked?
  end

  test "registration requires terms and preserves safe fields across language changes" do
    visit new_registration_path

    assert_button "Crear cuenta", disabled: true
    find("#user_accept_terms").check
    assert_button "Crear cuenta", disabled: false
    assert_not find("#user_accept_operational_email").checked?
    find("#user_accept_operational_email").check
    assert_button "Crear cuenta", disabled: false
    find("#user_accept_operational_email").uncheck
    assert_button "Crear cuenta", disabled: false
    find("#user_accept_terms").uncheck
    assert_button "Crear cuenta", disabled: true
    find("#user_accept_terms").check

    fill_in "Nombre", with: "Ada"
    fill_in "Apellidos", with: "Lovelace"
    fill_in "Email", with: "ada@example.com"
    fill_in "Contraseña", with: "never-preserve-this"
    fill_in "Repite tu contraseña", with: "never-preserve-this"
    find("input.language-selector-button[value='CAT']").click

    assert_current_path new_registration_path
    assert_field "Nom", with: "Ada"
    assert_field "Cognoms", with: "Lovelace"
    assert_field "Email", with: "ada@example.com"
    assert_equal "", find("input[name='user[password]']").value
    assert_button "Crear compte", disabled: false
  end

  test "landing keeps sticky navigation and responsive soft snap behavior" do
    visit new_quote_path

    assert_equal "sticky", page.evaluate_script("getComputedStyle(document.querySelector('.site-header')).position")
    assert_equal "y mandatory", page.evaluate_script("getComputedStyle(document.documentElement).scrollSnapType")
    assert_equal "smooth", page.evaluate_script("getComputedStyle(document.documentElement).scrollBehavior")

    find("#quote_origin").click
    # CSSOM serializes the default proximity strictness as only the axis.
    assert_equal "y", page.evaluate_script("getComputedStyle(document.documentElement).scrollSnapType")

    page.driver.browser.manage.window.resize_to(390, 844)
    assert_equal "y", page.evaluate_script("getComputedStyle(document.documentElement).scrollSnapType")
    assert_equal "sticky", page.evaluate_script("getComputedStyle(document.querySelector('.site-header')).position")
  end
end
