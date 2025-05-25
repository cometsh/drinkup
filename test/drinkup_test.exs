defmodule DrinkupTest do
  use ExUnit.Case
  doctest Drinkup

  test "greets the world" do
    assert Drinkup.hello() == :world
  end
end
