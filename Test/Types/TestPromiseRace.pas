unit TestPromiseRace;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Promises.Exceptions, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseRace = class
  public
    [Test]
    /// <summary>
    /// Race with multiple promises - the fastest one wins.
    /// </summary>
    procedure FastestPromiseWins;

    [Test]
    /// <summary>
    /// Race where the fastest rejects - the Race promise rejects.
    /// </summary>
    procedure FastestRejectsRaceRejects;

    [Test]
    /// <summary>
    /// Race where the fastest resolves and a slower one rejects - Race resolves.
    /// </summary>
    procedure FastestResolvesSlowerRejectsIgnored;

    [Test]
    /// <summary>
    /// Race with a single promise - behaves identically to that promise.
    /// </summary>
    procedure SinglePromise;

    [Test]
    /// <summary>
    /// Race with empty array - rejects with EArgumentException.
    /// </summary>
    procedure EmptyArrayRejects;

    [Test]
    /// <summary>
    /// Race used in a chain - .ThenBy after Race receives the winner's value.
    /// </summary>
    procedure RaceInChain;

    [Test]
    /// <summary>
    /// Race as a timeout pattern - one promise does real work, another raises after delay.
    /// </summary>
    procedure RaceAsTimeoutPattern;

    [Test]
    /// <summary>
    /// Stress test: Race with many concurrent promises.
    /// </summary>
    procedure StressTestManyPromises;
  end;

implementation

{ TTestPromiseRace }

procedure TTestPromiseRace.FastestPromiseWins;
var
  LFastSignal: TEvent;
  LSlowSignal: TEvent;
  LPromise: IPromise<Integer>;
begin
  LFastSignal := TEvent.Create;
  LSlowSignal := TEvent.Create;
  try
    LPromise := Promise.Race<Integer>([
      Promise.Resolve<Integer>(function: Integer
        begin
          LFastSignal.WaitFor;
          Result := 42;
        end),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSlowSignal.WaitFor;
          Result := 99;
        end)
    ]);

    // Release the fast one first
    LFastSignal.SetEvent;
    Assert.Resolves(LPromise);
    Assert.AreEqual(42, LPromise.Await);

    // Release slow one to prevent hanging threads
    LSlowSignal.SetEvent;
  finally
    LFastSignal.Free;
    LSlowSignal.Free;
  end;
end;

procedure TTestPromiseRace.FastestRejectsRaceRejects;
var
  LPromise: IPromise<Integer>;
  LSlowSignal: TEvent;
begin
  LSlowSignal := TEvent.Create;
  try
    LPromise := Promise.Race<Integer>([
      Promise.Reject<Integer>(ETestException.Create('fast error')),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSlowSignal.WaitFor;
          Result := 99;
        end)
    ]);

    Assert.Rejects(LPromise);
    LSlowSignal.SetEvent;
  finally
    LSlowSignal.Free;
  end;
end;

procedure TTestPromiseRace.FastestResolvesSlowerRejectsIgnored;
var
  LPromise: IPromise<Integer>;
  LSlowSignal: TEvent;
begin
  LSlowSignal := TEvent.Create;
  try
    LPromise := Promise.Race<Integer>([
      Promise.Resolve<Integer>(function: Integer
        begin
          Result := 42;
        end),
      Promise.Resolve<Integer>(function: Integer
        begin
          LSlowSignal.WaitFor;
          raise ETestException.Create('slow error');
        end)
    ]);

    Assert.Resolves(LPromise);
    Assert.AreEqual(42, LPromise.Await);
    LSlowSignal.SetEvent;
  finally
    LSlowSignal.Free;
  end;
end;

procedure TTestPromiseRace.SinglePromise;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Race<Integer>([
    Promise.Resolve<Integer>(function: Integer
      begin
        Result := 7;
      end)
  ]);

  Assert.Resolves(LPromise);
  Assert.AreEqual(7, LPromise.Await);
end;

procedure TTestPromiseRace.EmptyArrayRejects;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Race<Integer>([]);
  Assert.RejectsWith(LPromise, EArgumentException);
end;

procedure TTestPromiseRace.RaceInChain;
var
  LPromise: IPromise<String>;
begin
  LPromise := Promise.Race<Integer>([
    Promise.Resolve<Integer>(function: Integer
      begin
        Result := 42;
      end)
  ])
  .Op.ThenBy<String>(function(const V: Integer): String
    begin
      Result := IntToStr(V);
    end);

  Assert.Resolves(LPromise);
  Assert.AreEqual('42', LPromise.Await);
end;

procedure TTestPromiseRace.RaceAsTimeoutPattern;
var
  LPromise: IPromise<Integer>;
begin
  // The timeout promise resolves faster than the "slow work" promise
  LPromise := Promise.Race<Integer>([
    Promise.Resolve<Integer>(function: Integer
      begin
        Sleep(5000); // Slow work
        Result := 42;
      end),
    Promise.Resolve<Integer>(function: Integer
      begin
        Sleep(50); // Short timeout
        raise ETimeoutException.Create('Operation timed out');
      end)
  ]);

  Assert.RejectsWith(LPromise, ETimeoutException);
end;

procedure TTestPromiseRace.StressTestManyPromises;
var
  LPromises: TArray<IPromise<Integer>>;
  LSignals: TArray<TEvent>;
  LPromise: IPromise<Integer>;
  i: Integer;
const
  COUNT = 20;
begin
  SetLength(LPromises, COUNT);
  SetLength(LSignals, COUNT);

  for i := 0 to COUNT - 1 do
  begin
    LSignals[i] := TEvent.Create;
    var LIndex := i;
    var LSignal := LSignals[i];
    LPromises[i] := Promise.Resolve<Integer>(function: Integer
      begin
        LSignal.WaitFor;
        Result := LIndex;
      end);
  end;

  LPromise := Promise.Race<Integer>(LPromises);

  // Signal the 5th promise first
  LSignals[5].SetEvent;

  Assert.Resolves(LPromise);
  Assert.AreEqual(5, LPromise.Await);

  // Clean up - signal all remaining
  for i := 0 to COUNT - 1 do
  begin
    LSignals[i].SetEvent;
    LSignals[i].Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseRace);

end.
